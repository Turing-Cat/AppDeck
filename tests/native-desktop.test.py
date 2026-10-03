"""Run on a live Omarchy desktop with Qt6Widgets development tools.

Creates three temporary windows, restores the previous focus, and checks the
native socket against a local responder. Never sends Kill to the desktop.
"""
import json, pathlib, socket, subprocess, tempfile, threading, time
repo=pathlib.Path(__file__).resolve().parents[1]
def run(args, **kwargs):
 return subprocess.check_output(args,text=True,**kwargs).strip()
def hypr(cmd):return run(['hyprctl','dispatch',cmd])
original=json.loads(run(['hyprctl','-j','activewindow'])).get('address')
processes=[]
try:
 with tempfile.TemporaryDirectory(prefix='appdeck-native-') as tmp:
  d=pathlib.Path(tmp)
  (d/'windows.cpp').write_text('''#include <QApplication>
#include <QLabel>
int main(int argc,char**argv){QApplication app(argc,argv);app.setDesktopFileName("appdeck-refactor-check");QLabel a("First"),b("Second"),c("Third");a.setWindowTitle("AppDeck Refactor First");b.setWindowTitle("AppDeck Refactor Second");c.setWindowTitle("AppDeck Refactor Third");a.resize(400,200);b.resize(400,200);c.resize(400,200);a.show();b.show();c.show();return app.exec();}''')
  flags=run(['pkg-config','--cflags','--libs','Qt6Widgets']).split()
  subprocess.run(['c++',str(d/'windows.cpp'),'-o',str(d/'windows'),*flags],check=True)
  f=(d/'windows.log').open('w');helper=subprocess.Popen([str(d/'windows')],stdout=f,stderr=f);processes.append(helper)
  clients=[]
  for _ in range(40):
   clients=[c for c in json.loads(run(['hyprctl','-j','clients'])) if c['pid']==helper.pid]
   if len(clients)==3:break
   time.sleep(.1)
  assert len(clients)==3,clients
  used={c['workspace']['id'] for c in json.loads(run(['hyprctl','-j','clients']))}
  spaces=[i for i in range(101,150) if i not in used][:2]
  for c,ws in zip(clients[:2],spaces):
   hypr('hl.dsp.window.move({window="address:'+c['address']+'",workspace='+str(ws)+',follow=false})')
  (d/'Commons').symlink_to('/usr/share/omarchy/shell/Commons');(d/'Ui').symlink_to('/usr/share/omarchy/shell/Ui')
  (d/'shell.qml').write_text('''import QtQuick
import Quickshell
import Quickshell.Io
ShellRoot {
 id: test
 property var app: null
 property var socketResult: null
 property var request: null
 Component.onCompleted: {
  var c=Qt.createComponent("file://'''+str(repo)+'''/AppDeck.qml")
  if(c.status !== Component.Ready)throw new Error(c.errorString())
  app=c.createObject(test)
 }
 IpcHandler {
  target: "refactorcheck"
  function startRequest(path: string): string {
   test.socketResult=null
   var c=Qt.createComponent("file://'''+str(repo)+'''/AppDeckKillRequest.qml")
   test.request=c.createObject(test,{command:"harmless-test-command",path:path})
   test.request.completed.connect(function(ok){test.socketResult=ok})
   test.request.start()
   return JSON.stringify({started:true})
  }
  function socketStatus(): string { return JSON.stringify({result:test.socketResult}) }
  function openPanel(): string { test.app.open("{}");test.app.setSearchQuery("appdeck-refactor-check");return status() }
  function choose(id: string): string { test.app.chooseWindow(id);return status() }
  function activate(): string { test.app.focusSelectedApp();return status() }
  function status(): string { return JSON.stringify({opened:test.app.opened,pending:!!test.app.pendingFocusHandle,message:test.app.footerMessage,selected:test.app.selectedWindowId,apps:test.app.apps.map(function(a){return {name:a.name,windows:a.windows.map(function(w){return {id:w.id,title:w.title,workspace:w.workspace}})}})}) }
 }
}''')
  log=(d/'shell.log').open('w');qs=subprocess.Popen(['quickshell','-p',str(d/'shell.qml'),'--no-color'],stdout=log,stderr=log);processes.append(qs)
  def ipc(method,*args):return json.loads(run(['quickshell','ipc','--pid',str(qs.pid),'call','refactorcheck',method,*args],stderr=subprocess.DEVNULL))
  for _ in range(40):
   try:ipc('status');break
   except subprocess.CalledProcessError:time.sleep(.1)
  results=[]
  for c in clients[:2]:
   state=ipc('openPanel');assert len(state['apps'])==1,state
   windows=state['apps'][0]['windows'];assert len(windows)==3,windows
   w=next(w for w in windows if w['id']==c['address'])
   ipc('choose',w['id']);ipc('activate')
   time.sleep(.4)
   active=json.loads(run(['hyprctl','-j','activewindow']))
   state=ipc('status')
   assert active['address']==w['id'] and not state['opened'] and not state['pending'],(active,state)
   results.append({'window':w['title'],'workspace':active['workspace']['id'],'focus':'passed'})
  # The real transport talks only to this local non-destructive responder.
  for mode in ["fragmented-ok", "error", "timeout"]:
   path=str(d/'kill.sock')
   if pathlib.Path(path).exists():pathlib.Path(path).unlink()
   listener=socket.socket(socket.AF_UNIX,socket.SOCK_STREAM)
   listener.bind(path);listener.listen(1);listener.settimeout(5)
   received=[]
   def respond():
    with listener:
     connection,_=listener.accept()
     with connection:
      received.append(connection.recv(4096).decode())
      if mode=="timeout":time.sleep(1.7)
      elif mode=="error":connection.sendall(b"invalid command")
      else:
       connection.sendall(b"o");time.sleep(.03);connection.sendall(b"k\n")
   responder=threading.Thread(target=respond,daemon=True);responder.start()
   ipc('startRequest',path)
   result=None
   for _ in range(40):
    result=ipc('socketStatus')['result']
    if result is not None:break
    time.sleep(.05)
   responder.join(timeout=5)
   assert received==['dispatch harmless-test-command'],received
   assert result==(mode=="fragmented-ok"),(mode,result)
   results.append({'socket':mode,'result':'passed'})
  print(json.dumps(results,ensure_ascii=False))
  qs.terminate();qs.wait(timeout=5);processes.remove(qs)
  log.close();logs=(d/'shell.log').read_text()
  assert 'ReferenceError:' not in logs and 'TypeError:' not in logs,logs
finally:
 for proc in reversed(processes):
  if proc.poll() is None:
   proc.terminate();proc.wait(timeout=5)
 if original:hypr('hl.dsp.focus({window="address:'+original+'"})')
