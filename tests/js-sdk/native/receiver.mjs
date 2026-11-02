import http from 'node:http';
http.createServer((request,response)=>{
  let body='';
  request.on('data',data=>{body+=data;});
  request.on('end',()=>{
    if(body.length<2000)console.log(new Date().toISOString(),body);
    response.end('ok');
  });
}).listen(8094,'127.0.0.1',()=>console.log('Probe receiver on localhost8094'));
