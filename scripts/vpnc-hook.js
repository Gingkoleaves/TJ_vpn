// OpenConnect on Windows invokes hooks via cscript, not a command shell.
var shell = new ActiveXObject('WScript.Shell');
var env = shell.Environment('Process');
var fs = new ActiveXObject('Scripting.FileSystemObject');
var hook = fs.BuildPath(fs.GetParentFolderName(WScript.ScriptFullName), 'VpnHook.ps1');
var config = env('CAMPUS_CONFIG_PATH');
if (!config || config.indexOf('"') !== -1) WScript.Quit(1);
var powershell = env('SystemRoot') + '\\System32\\WindowsPowerShell\\v1.0\\powershell.exe';
WScript.Quit(shell.Run('"' + powershell + '" -NoProfile -ExecutionPolicy Bypass -File "' + hook + '" -ConfigPath "' + config + '"', 0, true));
