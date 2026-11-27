/* CastiOS 0.37-exp1: original XP-inspired, keyboard-first Live installer.
 * Separate Multiboot module: never included in the installed kernel/image.
 * BIOS/whole disk only. All mutations are behind exact FORMAT hdX consent.
 */
typedef unsigned int u32;
typedef unsigned short u16;
typedef unsigned char u8;
#include "extensions/base.h"
#include "extensions/gfx.h"
struct install_api {
 struct ext_api *ext;
 u32 *payload_size;
 u8 *flush_cap;
 char *models;
 void (*seed)(void);
 void (*select)(u32);
};
#define FS_BASE 32768U
#define FS_SECTORS 7681U
#define MIRROR (FS_BASE+8192U)
static struct install_api *A;
static int graphical;
static u32 target, completed, total, last_percent;
static u8 verify_buf[512];
static const char *steps[]={"1  Bienvenida","2  Elegir disco","3  Confirmar borrado","4  Copiar y verificar","5  Finalizar"};
static void logmsg(const char *s){while(*s){u8 c=*s++;__asm__ volatile("outb %0,$0xe9"::"a"(c));}}
static void say(const char *s){if(graphical)logmsg(s);else xs(s);}
static void text(u32 x,u32 y,const char*s,u32 c){gfx_text(x,y,s,c);}
static void num(char *b,u32 n){char rev[11];u32 k=0,j=0;do{rev[k++]=(char)('0'+n%10);n/=10;}while(n);while(k)b[j++]=rev[--k];b[j]=0;}
static void frame(u32 step,const char *title){
 gfx_rect(0,0,*X.fb_width,*X.fb_height,0x315ba6);
 gfx_rect(32,32,960,68,0x153b7a);
 text(58,48,"CastiOS",0xffffff);text(58,74,"0.37-exp1  /  Instalacion experimental",0xb8d5ff);
 gfx_rect(32,100,248,620,0x224b90);
 for(u32 i=0;i<5;i++)text(48,145+i*60,steps[i],i==step?0xffffff:0x9ebde9);
 gfx_rect(280,100,712,620,0xf0eee5);
 text(308,130,title,0x14386d);
 gfx_rect(304,164,664,2,0xc5c4be);
 gfx_rect(280,654,712,66,0xd9d8d0);
 text(308,681,step==3?"Espera a que termine. No apagues el equipo.":
      step==4?"Enter / Esc: volver a la terminal":"Enter: continuar   Esc: cancelar/volver",0x26354a);
}
static void message(u32 y,const char*s){text(308,y,s,0x283b54);}
static int valid(u32 t){return t<4 && X.caps[t]>=MIRROR+FS_SECTORS && A->flush_cap[t]==1;}
static int ready(void){return *A->payload_size>=512 && *A->payload_size<=0x800000 && !(*A->payload_size%512) && !*X.process_count && !*X.process_active;}
static void progress(const char *phase,int force){
 u32 percent=completed*100/total;
 if(!force && percent==last_percent)return;
 last_percent=percent;
 if(graphical){
  gfx_rect(308,260,650,100,0xf0eee5);message(260,phase);
  gfx_rect(308,304,640,28,0x263f6e);gfx_rect(312,308,632*percent/100,20,0x4ba84a);
  char b[11];num(b,percent);text(308,344,b,0x283b54);text(340,344,"%",0x283b54);
 }
 if(force){say(phase);say("\n");}
}
static int transfer(u32 start,const u8 *data,u32 sectors,int verify){
 for(u32 n=0;n<sectors;n++){
  if(verify){
   if(X.read(target,start+n,verify_buf))return 0;
   for(u32 j=0;j<512;j++)if(verify_buf[j]!=data[n*512+j])return 0;
  }else if(X.write_sector(target,start+n,data+n*512))return 0;
  completed++;progress(verify?"Verificando lectura del disco...":"Copiando arranque y archivos...",0);
 }
 return 1;
}
static int install(void){
 /* Repeat preflight immediately before any RAM or disk mutation. */
 if(!ready()||!valid(target))return 0;
 u8 *payload=(u8*)0x800000;u32 bytes=*A->payload_size;
 for(u32 i=0;i+16<=bytes;i++){
  const char *tag="set asmdisk=hd";u32 j=0;
  while(j<14 && payload[i+j]==(u8)tag[j])j++;
  if(j==14 && payload[i+14]>='a' && payload[i+14]<='d')payload[i+14]=(u8)('a'+target);
 }
 A->select(target);A->seed();
 completed=0;total=2*(bytes/512+2*FS_SECTORS);last_percent=101;
 if(graphical){frame(3,"Instalando CastiOS");message(196,"No apagues el equipo ni retires el medio Live.");message(224,"El disco de destino ya puede contener cambios.");}
 progress("Copiando arranque y archivos...",1);
 if(!transfer(0,payload,bytes/512,0) ||
    !transfer(FS_BASE,(const u8*)0x200000,FS_SECTORS,0) ||
    !transfer(MIRROR,(const u8*)0x200000,FS_SECTORS,0))return 0;
 if(X.flush_disk())return 0;
 progress("Verificando lectura del disco...",1);
 if(!transfer(0,payload,bytes/512,1) ||
    !transfer(FS_BASE,(const u8*)0x200000,FS_SECTORS,1) ||
    !transfer(MIRROR,(const u8*)0x200000,FS_SECTORS,1))return 0;
 *X.persistent_fs=1;
 return 1;
}
static int exact(const char*a,const char*b){while(*a&&*a==*b){a++;b++;}return *a==*b;}
static int confirm(void){
 char wanted[]="FORMAT hda",input[11];u32 n=0;wanted[9]=(char)('a'+target);input[0]=0;
 if(graphical){
  frame(2,"Confirmar instalacion en disco completo");
  message(196,"ATENCION: se borraran las particiones y los datos.");
  message(224,"No es una instalacion dual boot ni una actualizacion.");
  message(260,"Para continuar, escribe exactamente:");text(308,292,wanted,0xa82020);
 }else{xs("ATENCION: se borrara el disco elegido, sus particiones y datos.\n");xs(wanted);xs("\n");}
 say("SETUP CONFIRM\n");
 for(;;){
  if(graphical){gfx_rect(308,330,500,32,0xffffff);text(316,338,input,0x122e59);}
  u32 k=X.key();
  if(k==27)return 0;
  if(k==13||k==10){
   if(!graphical)X.out(10);
   if(exact(input,wanted))return 1;
   if(!graphical)return 0;
   message(390,"No coincide. Corrige el texto o pulsa Esc.");say("SETUP MISMATCH\n");
  }else if(k==8){if(n){input[--n]=0;if(!graphical)X.out(8);}}
  else if(k>=32&&k<=126&&n<10){input[n++]=(char)k;input[n]=0;if(!graphical)X.out(k);}
 }
}
static void disks(void){
 frame(1,"Selecciona el disco de destino");
 message(190,"Pulsa 1, 2, 3 o 4 para seleccionar; Enter confirma.");
 message(214,"Capacidad accesible en MiB. Se usa el disco completo.");
 for(u32 i=0;i<4;i++){
  u32 y=258+76*i;char label[]="1  hda";char size[11];
  label[0]=(char)('1'+i);label[5]=(char)('a'+i);
  gfx_rect(300,y-8,668,68,i==target?0xc7dbf5:0xe2e1da);
  text(312,y,label,0x14386d);num(size,X.caps[i]/2048);text(400,y,size,0x14386d);
  text(490,y,valid(i)?"MiB  / disponible":"MiB  / no instalable",valid(i)?0x1a6530:0x954040);
  char model[42];u32 j;for(j=0;j<40&&A->models[i*41+j];j++)model[j]=A->models[i*41+j];model[j]=0;
  text(312,y+26,model,0x283b54);
 }
 say("SETUP DISKS\n");
}
void installer_entry(struct install_api *api,const char *args){
 A=api;X=*api->ext;graphical=!*args;
 if(graphical&&!gfx_available()){xs("Sin framebuffer. Usa install hda|hdb|hdc|hdd.\n");return;}
 if(!ready()){xs("Instalacion rechazada: usa ISO Live y termina las tareas bg.\n");return;}
 if(!graphical){
  if(args[0]!='h'||args[1]!='d'||args[2]<'a'||args[2]>'d'||args[3]){xs("Uso: install hda|hdb|hdc|hdd\n");return;}
  target=(u32)(args[2]-'a');
  if(!valid(target)){xs("Instalacion rechazada: disco ausente, no compatible o pequeno.\n");return;}
  if(!confirm()){xs("Instalacion cancelada. Discos sin cambios.\n");return;}
 }else{
  frame(0,"Bienvenido al asistente de CastiOS");
  message(202,"Instalador Live para PC BIOS de 32 bits.");
  message(242,"Instala arranque GRUB, kernel y archivos del sistema.");
  message(282,"Necesitas un disco de pruebas que puedas borrar.");
  message(322,"Version experimental. No conserva otros sistemas.");
  message(362,"Interfaz de teclado inspirada en instaladores clasicos.");
  say("SETUP WELCOME\n");
  for(;;){u32 k=X.key();if(k==27)goto cancel;if(k==13||k==10)break;}
  target=4;for(u32 i=0;i<4;i++)if(valid(i)){target=i;break;}
  for(;;){
   disks();
   for(;;){
    u32 k=X.key();if(k==27)goto cancel;
    if(k>='1'&&k<='4'){target=k-'1';disks();}
    if((k==13||k==10)&&valid(target))break;
   }
   if(confirm())break;
  }
 }
 int ok=install();
 if(graphical){
  frame(4,ok?"Instalacion completada":"La instalacion no se ha completado");
  message(208,ok?"Copia, vaciado de cache y lectura verificados.":"Fallo de E/S o verificacion. El destino puede estar incompleto.");
  message(250,ok?"Retira la ISO y arranca desde el disco seleccionado.":"Conserva el medio Live y revisa la unidad antes de reintentar.");
  message(292,"Enter o Esc: regresar a la terminal.");
 }
 say(ok?"Formateado e instalado. Retira la ISO y arranca desde ese disco.\n":"Error ATA durante instalacion: destino incompleto, datos en RAM.\n");
 if(graphical)for(;;){u32 k=X.key();if(k==13||k==10||k==27)break;}
 return;
cancel:
 say("Instalacion cancelada. Discos sin cambios.\n");
}
