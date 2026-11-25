/* RMFS: volatile, paged, bounded namespace. Nodes are never persisted. */
#define RM_NODES 64
#define RM_PAGES 16
#define RM_SIZE (RM_PAGES*4096U)
struct rm_node {u32 used, dir, parent, length, pages[RM_PAGES];char name[32];};
/* Lazy metadata pages (32 nodes/page); no 7 KiB resident static table. */
static struct rm_node *R[RM_NODES];
_Static_assert(32*sizeof(struct rm_node)<=4096,"RMFS node page");
static int rm_meta(u32 i){
 if(R[i])return 1;
 u32 p=X.alloc();if(!p)return 0;
 u32 base=i&~31U;for(u32 j=0;j<32;j++)R[base+j]=((struct rm_node*)p)+j;
 return 1;
}
static int rm_name(const char *s,u32 n){
 if(!n||n>31)return 0;
 for(u32 i=0;i<n;i++){char c=s[i];if(!((c>='a'&&c<='z')||(c>='A'&&c<='Z')||(c>='0'&&c<='9')||c=='.'||c=='_'||c=='-'))return 0;}
 return !(n==1&&s[0]=='.')&&!(n==2&&s[0]=='.'&&s[1]=='.');
}
static int rm_find(u32 parent,const char *name){
 for(int i=0;i<RM_NODES;i++)if(R[i]&&R[i]->used&&R[i]->parent==parent&&eq(R[i]->name,name))return i;
 return -1;
}
/* Root is 0, node indices are stored as index+1 to keep root distinct. */
static int rm_resolve(const char *path,u32 *parent,char *name){
 if(!xprefix(path,"/ram")||(path[4]&&path[4]!='/'))return -3;
 u32 dir=0;const char*s=path+4;
 while(*s){while(*s=='/')s++;if(!*s)break;
  u32 n=0;while(s[n]&&s[n]!='/'){if(n==31)return -2;name[n]=s[n];n++;}name[n]=0;s+=n;
  if(eq(name,"."))continue;
  if(eq(name,"..")){if(dir)dir=R[dir-1]->parent;continue;}
  if(!rm_name(name,n))return -2;
  int found=rm_find(dir,name);const char*next=s;while(*next=='/')next++;
  if(!*next){*parent=dir;return found;}
  if(found<0||!R[found]->dir)return -2;
  dir=(u32)found+1;
 }
 name[0]=0;*parent=dir;return dir?(int)dir-1:-4;
}
static int rm_alloc(u32 parent,const char*name,int dir){
 int id=rm_find(parent,name);if(id>=0)return id;
 for(int i=0;i<RM_NODES;i++)if(!R[i]||!R[i]->used){if(!rm_meta(i))return -1;zero(R[i],sizeof *R[i]);R[i]->parent=parent;R[i]->dir=dir;R[i]->used=1;xcopy(R[i]->name,name,32);return i;}
 return -1;
}
static int rm_store(struct rm_node *f,const u8 *src,u32 n,int append){
 if(f->dir||n>RM_SIZE||(append&&f->length>RM_SIZE-n))return 0;
 u32 base=append?f->length:0,end=base+n,need=(end+4095)/4096;
 u32 added[RM_PAGES],count=0;
 for(u32 i=0;i<need;i++)if(!f->pages[i]){u32 page=X.alloc();if(!page){for(u32 j=0;j<count;j++){X.free(f->pages[added[j]]);f->pages[added[j]]=0;}return 0;}f->pages[i]=page;added[count++]=i;}
 for(u32 i=0;i<n;){u32 at=base+i,take=4096-(at&4095);if(take>n-i)take=n-i;memcopy((u8*)f->pages[at>>12]+(at&4095),src+i,take);i+=take;}
 f->length=end;
 if(!append)for(u32 i=need;i<RM_PAGES;i++)if(f->pages[i]){X.free(f->pages[i]);f->pages[i]=0;}
 return 1;
}
static void rm_release(u32 id){
 struct rm_node*f=R[id];for(u32 i=0;i<RM_PAGES;i++)if(f->pages[i])X.free(f->pages[i]);zero(f,sizeof *f);
 u32 base=id&~31U;for(u32 j=0;j<32;j++)if(R[base+j]->used)return;
 u32 p=(u32)R[base];for(u32 j=0;j<32;j++)R[base+j]=0;X.free(p);
}
static int rm_load(const char*path,u8*out,u32 limit){u32 parent;char name[32];int id=rm_resolve(path,&parent,name);if(id<0||R[id]->dir||R[id]->length>limit)return -1;for(u32 i=0;i<R[id]->length;){u32 n=R[id]->length-i;if(n>4096)n=4096;memcopy(out+i,(void*)R[id]->pages[i>>12],n);i+=n;}return (int)R[id]->length;}
static int rm_command(const char*cmd,const char*args,const char*path){
 u32 parent;char name[32];int id=rm_resolve(path,&parent,name);
 if(id==-3)return 0;
 if(eq(cmd,"cd")){if(id==-4||(id>=0&&R[id]->dir)){xcopy(vcwd,path,256);return 1;}return xerr("RMFS: carpeta inexistente");}
 if(eq(cmd,"ls")){if(id==-4)parent=0;else if(id>=0){if(R[id]->dir)parent=id+1;else{xs(R[id]->name);xs(" ");xn(R[id]->length);xs(" bytes RMFS\n");return 1;}}else return xerr("RMFS: ruta inexistente");
  for(int i=0;i<RM_NODES;i++)if(R[i]&&R[i]->used&&R[i]->parent==parent){xs(R[i]->name);if(R[i]->dir)xs("/");xs(" ");xn(R[i]->length);xs("\n");}
  return 1;}
 if(eq(cmd,"stat")){if(id<0)return xerr("RMFS: archivo inexistente");xs(path);if(R[id]->dir)xs(" directorio RMFS\n");else{xs(" ");xn(R[id]->length);xs(" bytes RMFS volatil\n");}return 1;}
 if(eq(cmd,"cat")||eq(cmd,"type")){if(id<0||R[id]->dir)return xerr("RMFS: archivo inexistente");for(u32 i=0;i<R[id]->length;i++)X.out(((u8*)R[id]->pages[i/4096])[i%4096]);X.out('\n');return 1;}
 if(eq(cmd,"mkdir")||eq(cmd,"touch")){if(id>=0||!name[0]||id!=-1)return xerr("RMFS: ruta ocupada o invalida");if(rm_alloc(parent,name,eq(cmd,"mkdir"))<0)return xerr("RMFS: 64 nodos agotados");return 1;}
 if(eq(cmd,"rm")){if(id<0)return xerr("RMFS: archivo inexistente");if(R[id]->dir){for(int j=0;j<RM_NODES;j++)if(R[j]&&R[j]->used&&R[j]->parent==(u32)id+1)return xerr("RMFS: carpeta no vacia");}rm_release(id);return 1;}
 if(eq(cmd,"write")||eq(cmd,"append")){
  if(id==-4||id==-2)return xerr("RMFS: ruta invalida");
  if(id<0){if(!name[0])return xerr("RMFS: falta nombre");id=rm_alloc(parent,name,0);if(id<0)return xerr("RMFS: 64 nodos agotados");}
  if(R[id]->dir)return xerr("RMFS: es una carpeta");
  const char *s=args;while(*s&&*s!=' ')s++;while(*s==' ')s++;
  u8 line[256];u32 len=strlen_(s),n=0;
  if(eq(cmd,"append")&&R[id]->length)line[n++]='\n';
  if(len>sizeof line-n)return xerr("RMFS: linea demasiado larga");
  memcopy(line+n,s,len);n+=len;
  if(!rm_store(R[id],line,n,eq(cmd,"append")))return xerr("RMFS: archivo maximo 64 KiB o sin RAM");
  return 1;
 }
 return xerr("RMFS: comando no disponible");
}

static int rm_info(void){u32 nodes=0,pages=0;for(u32 i=0;i<RM_NODES;i++)if(R[i]&&R[i]->used){nodes++;for(u32 j=0;j<RM_PAGES;j++)if(R[i]->pages[j])pages++;}
 xs("RMFS /ram: ");xn(nodes);xs("/64 nodos, ");xn(pages);xs(" paginas de 4 KiB usadas, max 64 KiB/archivo; volatil.\n");return 1;}
