// Expo 57's root buildscript otherwise resolves Kotlin 2.1 through RN's plugin,
// even when android.kotlinVersion changes the stdlib to 2.3. Ditto 5.2's rustls
// dependency requires readable 2.3 metadata. Keep the compiler and property aligned.
const VERSION = '2.3.0';

function pinKotlinCompiler(contents) {
  const dependency = /classpath\(\s*(['"])org\.jetbrains\.kotlin:kotlin-gradle-plugin(?::[^'"]+)?\1\s*\)/g;
  const matches = contents.match(dependency);
  if (!matches || matches.length !== 1) {
    throw new Error('Expected one Kotlin Gradle plugin classpath in the Expo 57 root build.gradle; review the template before applying this version-specific plugin.');
  }
  return contents.replace(dependency, `classpath('org.jetbrains.kotlin:kotlin-gradle-plugin:${VERSION}')`);
}

module.exports = function withKotlinCompiler(config) {
  const { withProjectBuildGradle } = require('@expo/config-plugins');
  return withProjectBuildGradle(config, config => {
    if (config.modResults.language !== 'groovy') {
      throw new Error('This Expo 57 starter plugin expects a Groovy root build.gradle');
    }
    config.modResults.contents = pinKotlinCompiler(config.modResults.contents);
    return config;
  });
};
module.exports.pinKotlinCompiler = pinKotlinCompiler;
