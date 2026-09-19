import net from 'node:net';
import { spawn } from 'node:child_process';

// Each Codex task owns stdio, while one authenticated loopback broker owns the editor.
// No mutation is replayed, including after a broken client connection.
export class SharedClient {
  constructor(config, Lines) { this.config=config; this.Lines=Lines; this.pending=new Map(); this.seq=0; }
  connect() {
    return new Promise((resolve,reject)=>{
      const socket=net.createConnection({host:'127.0.0.1',port:this.config.port});
      this.socket=socket;
      let ready=false;
      const timer=setTimeout(()=>{socket.destroy();reject(new Error('Broker handshake timed out. Stop an old v0.1 bridge if it owns this port.'));},2000);
      const parser=new this.Lines(line=>{
        const message=JSON.parse(line);
        if (!ready) {
          if (message.event!=='client_ready' || message.protocol!==2) { socket.destroy(); return; }
          ready=true;clearTimeout(timer);resolve();return;
        }
        const pending=this.pending.get(message.id);
        if(!pending)return;
        this.pending.delete(message.id);clearTimeout(pending.timer);
        message.ok ? pending.resolve(message.result) : pending.reject(new Error(message.error||'Broker request failed.'));
      });
      socket.on('connect',()=>socket.write(JSON.stringify({event:'client',protocol:2,token:this.config.token})+'\n'));
      socket.on('data',chunk=>{try{parser.push(chunk);}catch{socket.destroy();}});
      socket.on('error',error=>{if(!ready){clearTimeout(timer);reject(error);}});
      socket.on('close',()=>{
        clearTimeout(timer);
        if(!ready)reject(new Error('Broker closed during handshake. Stop the old bridge and restart MCP.'));
        for(const p of this.pending.values()){clearTimeout(p.timer);p.reject(new Error('Broker disconnected. An edit may have completed; inspect before retrying.'));}
        this.pending.clear();
      });
    });
  }
  async start(bridgePath) {
    try { await this.connect(); return; }
    catch(error) { if(error.code!=='ECONNREFUSED') throw error; }
    // Windows helper is hidden; detached broker outlives individual task clients.
    const broker=spawn(process.execPath,[bridgePath,'--broker'],{detached:true,windowsHide:true,stdio:'ignore',env:process.env});
    broker.on('error',()=>{});broker.unref();
    for(let i=0;i<20;i++) {
      await new Promise(resolve=>setTimeout(resolve,100));
      try { await this.connect();return; } catch(error) {if(error.code!=='ECONNREFUSED')throw error;}
    }
    throw new Error('Could not start shared C64 broker. Check Node path and local port.');
  }
  request(method,args,callId) {
    if(!this.socket || this.socket.destroyed)return Promise.reject(new Error('Broker disconnected; restart the MCP client.'));
    const id=++this.seq;
    return new Promise((resolve,reject)=>{
      const timer=setTimeout(()=>{this.socket.destroy();reject(new Error('Broker timed out. Inspect the project before retrying any edit.'));},16000);
      this.pending.set(id,{resolve,reject,timer,callId});
      this.socket.write(JSON.stringify({id,method,args})+'\n');
    });
  }
  status(){return this.request('status',{},null);}
  cancel(callId){for(const [id,p] of this.pending)if(p.callId===callId)this.socket.write(JSON.stringify({event:'cancel',id})+'\n');}
  async close(){this.socket?.destroy();}
}
