import { useEffect, useRef, useState } from 'react';
import { Text, ScrollView } from 'react-native';
import { SafeAreaProvider, SafeAreaView } from 'react-native-safe-area-context';
import { createRuntime } from './runtime';
import { DittoProvider, useDitto, useDittoQuery } from './DittoProvider';
import { decodeTask, saveTask, setTaskDone, deleteTask, TASK_QUERY, type Task } from './tasks';
import { requestMeshPermissions } from './permissions';
import config from '../config.local.json';
const runtime = createRuntime({databaseID: config.databaseID, persistenceDirectory: 'ditto-ios-probe', connection: {mode:'smallPeersOnly', offlineLicense:config.offlineLicense}, onAuthError: () => {}});
async function report(message: string) {
  console.log('DITTO_IOS_PROBE',message);
  await fetch('http://localhost:8094/result', {method:'POST',body:message}).catch(()=>{});
}
function Probe() {
  const ditto = useDitto();
  const {rows, loading, error} = useDittoQuery(TASK_QUERY,decodeTask);
  const state = useRef({rows,loading,error}); state.current={rows,loading,error};
  const once=useRef(false);
  const [messages,setMessages]=useState<string[]>([]);
  useEffect(()=>{
    if(once.current)return;once.current=true;
    const log=async(message:string)=>{setMessages(x=>[...x,message]);await report(message);};
    const waitFor=async(test:(rows:Task[])=>boolean)=>{
      const until=Date.now()+10000;
      while(Date.now()<until){
        if(state.current.error)throw new Error('observer error');
        if(!state.current.loading&&test(state.current.rows))return;
        await new Promise(resolve=>setTimeout(resolve,30));
      }
      throw new Error('observer timeout');
    };
    void (async()=>{
      const permissions=await requestMeshPermissions();
      if(!permissions.granted)throw new Error('iOS permission adapter rejected');
      await log('PASS permission adapter and provider startup');
      await waitFor(()=>true);
      const persistent='ios-probe-persist';
      if(state.current.rows.some(x=>x._id===persistent)){
        if(!state.current.rows.some(x=>x._id===persistent&&x.title==='Persist after process relaunch'&&!x.done))throw new Error('persistence mismatch');
        await log('PASS persisted row restored after process relaunch');
        await deleteTask(ditto,persistent);await waitFor(xs=>!xs.some(x=>x._id===persistent));
        await log('PASS persistence cleanup observed');
        await log('COMPLETE');return;
      }
      const id='ios-probe-crud';
      await saveTask(ditto,{_id:id,title:'iOS native task',done:false});
      await waitFor(xs=>xs.some(x=>x._id===id&&x.title==='iOS native task'&&!x.done));await log('PASS insert and provider observer');
      await setTaskDone(ditto,id,true);await waitFor(xs=>xs.some(x=>x._id===id&&x.done));await log('PASS complete observed');
      await setTaskDone(ditto,id,false);await waitFor(xs=>xs.some(x=>x._id===id&&!x.done));await log('PASS reopen observed');
      await deleteTask(ditto,id);await waitFor(xs=>!xs.some(x=>x._id===id));await log('PASS delete observed');
      await saveTask(ditto,{_id:persistent,title:'Persist after process relaunch',done:false});await waitFor(xs=>xs.some(x=>x._id===persistent));
      await log('READY_FOR_PROCESS_RELAUNCH');
    })().catch(async()=>{await log('FAIL native integration probe');});
  },[ditto]);
  return <ScrollView><Text>Native integration probe (automated, not UI interaction)</Text>{messages.map((x,i)=><Text key={i}>{x}</Text>)}<Text>Observer rows: {rows.length}</Text></ScrollView>;
}
export default function App(){return <SafeAreaProvider><SafeAreaView style={{flex:1}}><DittoProvider runtime={runtime} loading={<Text>Opening probe database</Text>} failure={()=>{void report('FAIL provider open');return <Text>Provider failed</Text>;}}><Probe/></DittoProvider></SafeAreaView></SafeAreaProvider>;}
