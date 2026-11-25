import subprocess,time,json,select,tempfile,os,shlex
from pathlib import Path
from PIL import Image

# Requires QEMU and Pillow; execute from the project root after make x64.
with tempfile.TemporaryDirectory() as tmp:
 log=Path(tmp)/'log'; shot=Path(tmp)/'screen.ppm'
 args=['qemu-system-x86_64','-accel','tcg','-display','none','-serial','none','-monitor','none','-nic','none','-no-reboot','-boot','d','-cdrom','dist/CastiOS-x64-preview.iso','-qmp','stdio','-debugcon','file:'+str(log)]+shlex.split(os.environ.get('QEMU_EXTRA_ARGS',''))
 p=subprocess.Popen(args,stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
 def qmp(cmd,args=None):
  p.stdin.write((json.dumps({'execute':cmd,'arguments':args or {}})+'\n').encode());p.stdin.flush()
  while True:
   line=json.loads(p.stdout.readline())
   if 'error' in line: raise Exception(line)
   if 'return' in line:return line['return']
 try:
  json.loads(p.stdout.readline());qmp('qmp_capabilities')
  for _ in range(300):
   if log.exists() and 'x64> ' in log.read_text(errors='replace'):break
   time.sleep(.1)
  else:raise Exception('No boot '+log.read_text(errors='replace'))
  qmp('screendump',{'filename':str(shot)})
  im=Image.open(shot).convert('RGB'); print('screen',im.size)
  assert im.size==(1024,768), 'not graphics mode'
  assert sum(1 for x in im.crop((0,0,640,400)).getdata() if x!=(0,0,0))>100, 'no text pixels'
  for _ in range(30):
   qmp('human-monitor-command',{'command-line':'sendkey ret 20'});time.sleep(.05)
  time.sleep(.5);qmp('screendump',{'filename':str(shot)})
  im=Image.open(shot).convert('RGB'); assert sum(1 for x in im.crop((0,384,640,400)).getdata() if x!=(0,0,0))>10
  print('Framebuffer screen and scrolling OK')
 finally:
  p.terminate();p.wait(timeout=5)
