static const u8 *desk_record(u32 i){return (const u8*)0x200000+512+i*8192;}
static int desk_nth(int n){
 u32 parent=*X.cwd;
 for(u32 i=0;i<480;i++){
  const u8*r=desk_record(i);
  if(r[0]&&le32(r+32)==parent&&le32(r+36)!=4){if(!n--)return (int)i;}
 }return -1;
}
static int desk_count(void){int n=0;while(desk_nth(n)>=0&&n<480)n++;return n;}
static void desk_number(u32 x,u32 y,u32 n){
 char b[11];int i=0;do{b[i++]='0'+n%10;n/=10;}while(n);char s[11];int k=0;while(i)s[k++]=b[--i];s[k]=0;desk_text(x,y,s,0xffffff);
}
static void desk_cursor(u32 x,u32 y){
 static const u16 edge[14]={0x800,0xc00,0xa00,0x900,0x880,0x840,0x820,
  0x810,0x808,0xff8,0x120,0x110,0x088,0x088};
 static const u16 fill[14]={0,0,0x400,0x600,0x700,0x780,0x7c0,
  0x7e0,0x7f0,0,0x0c0,0x0e0,0x070,0};
 for(u32 row=0;row<14;row++){
  volatile u32 *p=(volatile u32*)(*X.fb_address+(desk_y+y+row)*(*X.fb_pitch)+4*(desk_x+x));
  for(u32 col=0;col<12;col++){
   u16 bit=0x800U>>col;
   if(edge[row]&bit)p[col]=0x09131b;
   else if(fill[row]&bit)p[col]=0xffffff;
  }
 }
}
static void wm_app_paint(void){
 if(desk_view){
  if(desk_view==1){
   desk_text(316,154,"Archivos /  [Backspace: subir]",0x16374e);
   if(*X.cwd!=ROOT)desk_text(590,154,(const char*)desk_record(*X.cwd),0x16374e);
   int count=desk_count();
   for(int j=0;j<wm_rows&&desk_scroll+j<count;j++){
    int index=desk_scroll+j,id=desk_nth(index);const u8*r=desk_record(id);
    u32 y=185+j*25;
    if(index==desk_file)desk_box(310,y-4,590,23,0xb6d9ee);
    desk_text(321,y,le32(r+36)==2?"[DIR]":"[FILE]",0x235272);
    desk_text(391,y,(const char*)r,0x132e45);
   }
   if(!count)desk_text(321,191,"Carpeta vacia",0x345675);
  }else if(desk_view==4){
   const u8*r=desk_record((u32)desk_preview);
   desk_text(317,154,(const char*)r,0x16374e);
   u32 n=le32(r+40);if(n>600)n=600;
   char line[73];u32 at=0,y=186;
   while(at<n&&y<488){u32 k=0;while(at<n&&k<70){u8 c=r[64+at++];if(c=='\n')break;line[k++]=(c>=32&&c<127)?c:'.';}line[k]=0;desk_text(317,y,line,0x132e45);y+=20;}
  }else if(desk_view==2){
   desk_text(317,164,"Tareas AX05 en segundo plano",0x16374e);
   int shown=0;
   if(*X.process_active==2)for(u32 i=0;i<*X.process_count&&i<4;i++){
    const u8*p=X.process_table+i*56;
    u32 state=le32(p+24);
    if(!state)continue;
    desk_text(320,195+shown*34,"PID",0x234665);
    desk_number(366,195+shown*34,le32(p+52));
    desk_text(470,195+shown*34,state==1?"Ejecutando":state==3?"Durmiendo":"Terminado",0x234665);
    shown++;
   }
   if(!shown)desk_text(320,205,"Sin tareas de fondo",0x345675);
  }else{
   desk_text(317,164,"Kernel x86 32 bits / framebuffer RGB32",0x16374e);
   desk_text(317,205,"Tiempo activo (segundos):",0x16374e);
   desk_number(535,205,*X.ticks/100);
   desk_text(317,247,"Teclado y mouse PS/2; HID USB EHCI",0x345675);
  }
 }
}
static void desk_file_open(void){
 int i=desk_nth(desk_file);if(i<0)return;
 const u8*r=desk_record((u32)i);
 if(le32(r+36)==2){*X.cwd=(u32)i;desk_file=0;desk_scroll=0;}
 else if(le32(r+36)==1){desk_preview=i;desk_view=4;}
}
