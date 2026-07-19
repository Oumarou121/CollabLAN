import React, { useState } from 'react';
import { 
  FileText, 
  FileArchive, 
  Video, 
  FileImage, 
  File,
  ArrowUpRight,
  ArrowDownLeft,
  CheckCircle2,
  XCircle,
  RefreshCw,
  FolderOpen,
  Paperclip,
  Send,
  MoreVertical,
  Search,
  ChevronDown
} from 'lucide-react';

// --- Mock Data ---
interface Peer {
  id: string;
  name: string;
  status: 'online' | 'offline';
  lastActivity: string;
  fileCount: number;
  initials: string;
  color: string;
}

interface Transfer {
  id: string;
  peerId: string;
  filename: string;
  size: string;
  direction: 'sent' | 'received';
  status: 'success' | 'progress' | 'failed';
  progress: number; // 0-100
  time: string;
  type: 'document' | 'archive' | 'video' | 'image' | 'other';
}

const PEERS: Peer[] = [
  { id: 'p1', name: 'Alice Martin', status: 'online', lastActivity: '10:42', fileCount: 12, initials: 'AM', color: 'bg-indigo-500' },
  { id: 'p2', name: 'Bob Dupont', status: 'online', lastActivity: '09:15', fileCount: 4, initials: 'BD', color: 'bg-emerald-500' },
  { id: 'p3', name: 'Clara Lefèvre', status: 'offline', lastActivity: 'Hier', fileCount: 1, initials: 'CL', color: 'bg-purple-500' },
  { id: 'p4', name: 'David Tremblay', status: 'offline', lastActivity: 'Lun.', fileCount: 7, initials: 'DT', color: 'bg-amber-500' }
];

const TRANSFERS: Transfer[] = [
  { id: 't1', peerId: 'p1', filename: 'Design_Assets_V2.zip', size: '145.2 Mo', direction: 'received', status: 'progress', progress: 68, time: 'Maintenant', type: 'archive' },
  { id: 't2', peerId: 'p1', filename: 'Rapport_Q2.pdf', size: '4.2 Mo', direction: 'sent', status: 'success', progress: 100, time: '10:30', type: 'document' },
  { id: 't3', peerId: 'p1', filename: 'Reunion_Notes.docx', size: '1.1 Mo', direction: 'received', status: 'success', progress: 100, time: 'Hier', type: 'document' },
  { id: 't4', peerId: 'p2', filename: 'Video_Promo_Finale.mp4', size: '840.0 Mo', direction: 'sent', status: 'failed', progress: 12, time: '09:14', type: 'video' },
  { id: 't5', peerId: 'p2', filename: 'Logo_Vectoriel.svg', size: '250 Ko', direction: 'received', status: 'success', progress: 100, time: 'Ven.', type: 'image' },
  { id: 't6', peerId: 'p4', filename: 'Build_v1.0.4.tar.gz', size: '1.2 Go', direction: 'sent', status: 'success', progress: 100, time: 'Lun.', type: 'archive' },
];

const getFileIcon = (type: Transfer['type']) => {
  switch (type) {
    case 'document': return <FileText size={18} className="text-blue-400" />;
    case 'archive': return <FileArchive size={18} className="text-amber-400" />;
    case 'video': return <Video size={18} className="text-purple-400" />;
    case 'image': return <FileImage size={18} className="text-emerald-400" />;
    default: return <File size={18} className="text-slate-400" />;
  }
};

export function SidebarLayout() {
  const [selectedPeerId, setSelectedPeerId] = useState<string>(PEERS[0].id);

  const selectedPeer = PEERS.find(p => p.id === selectedPeerId);
  const peerTransfers = TRANSFERS.filter(t => t.peerId === selectedPeerId);

  return (
    <div className="flex h-screen w-full bg-slate-950 text-slate-300 font-sans overflow-hidden selection:bg-indigo-500/30">
      
      {/* Left Sidebar - Peer List */}
      <aside className="w-80 flex-shrink-0 bg-slate-900 border-r border-slate-800 flex flex-col">
        {/* Sidebar Header */}
        <div className="h-16 px-5 flex items-center border-b border-slate-800 bg-slate-900/50 backdrop-blur-sm z-10">
          <h2 className="text-sm font-semibold text-slate-100 tracking-wide uppercase">Réseau Local</h2>
          <span className="ml-auto text-xs font-medium text-slate-500 bg-slate-800 px-2 py-0.5 rounded-full">
            {PEERS.filter(p => p.status === 'online').length} en ligne
          </span>
        </div>

        {/* Search / Filter (Visual only) */}
        <div className="p-4 border-b border-slate-800/50">
          <div className="relative">
            <Search size={14} className="absolute left-3 top-1/2 -translate-y-1/2 text-slate-500" />
            <input 
              type="text" 
              placeholder="Chercher un contact..." 
              className="w-full bg-slate-950 border border-slate-800 rounded-md py-1.5 pl-9 pr-3 text-sm focus:outline-none focus:border-indigo-500/50 focus:ring-1 focus:ring-indigo-500/50 transition-all placeholder:text-slate-600 text-slate-200"
            />
          </div>
        </div>

        {/* Peer List */}
        <div className="flex-1 overflow-y-auto p-2 space-y-1 custom-scrollbar">
          {PEERS.map(peer => {
            const isSelected = selectedPeerId === peer.id;
            return (
              <button
                key={peer.id}
                onClick={() => setSelectedPeerId(peer.id)}
                className={`w-full flex items-center gap-3 p-3 rounded-lg transition-all text-left group ${
                  isSelected 
                    ? 'bg-indigo-500/10 hover:bg-indigo-500/15 ring-1 ring-indigo-500/30' 
                    : 'hover:bg-slate-800/50'
                }`}
              >
                {/* Avatar */}
                <div className="relative">
                  <div className={`w-10 h-10 rounded-full flex items-center justify-center text-sm font-medium text-white shadow-sm ${peer.color}`}>
                    {peer.initials}
                  </div>
                  <div className={`absolute bottom-0 right-0 w-3 h-3 rounded-full border-2 border-slate-900 ${peer.status === 'online' ? 'bg-emerald-500' : 'bg-slate-500'}`} />
                </div>
                
                {/* Info */}
                <div className="flex-1 min-w-0">
                  <div className="flex justify-between items-baseline mb-1">
                    <h3 className={`text-sm font-medium truncate ${isSelected ? 'text-indigo-100' : 'text-slate-200'}`}>
                      {peer.name}
                    </h3>
                    <span className="text-[10px] text-slate-500 ml-2 whitespace-nowrap">
                      {peer.lastActivity}
                    </span>
                  </div>
                  <div className="flex items-center gap-2">
                    <span className={`text-[10px] px-1.5 py-0.5 rounded font-medium ${isSelected ? 'bg-indigo-500/20 text-indigo-300' : 'bg-slate-800 text-slate-400'}`}>
                      {peer.fileCount} {peer.fileCount > 1 ? 'fichiers' : 'fichier'}
                    </span>
                  </div>
                </div>
              </button>
            );
          })}
        </div>
        
        {/* Current User Profile Area */}
        <div className="p-4 border-t border-slate-800 bg-slate-900/50">
          <div className="flex items-center gap-3">
            <div className="w-8 h-8 rounded-full bg-slate-800 flex items-center justify-center text-xs font-medium text-slate-400">
              MOI
            </div>
            <div className="flex-1 min-w-0">
              <p className="text-sm font-medium text-slate-300 truncate">Mon Ordinateur</p>
              <p className="text-xs text-emerald-500 flex items-center gap-1">
                <span className="w-1.5 h-1.5 rounded-full bg-emerald-500 inline-block"></span>
                Visible sur le LAN
              </p>
            </div>
          </div>
        </div>
      </aside>

      {/* Right Panel - Active Peer & Transfers */}
      <main className="flex-1 flex flex-col min-w-0 bg-slate-950 relative">
        {selectedPeer ? (
          <>
            {/* Header */}
            <header className="h-16 px-8 border-b border-slate-800 flex flex-shrink-0 items-center justify-between bg-slate-950/80 backdrop-blur-md sticky top-0 z-20">
              <div className="flex items-center gap-4">
                <div className={`w-8 h-8 rounded-full flex items-center justify-center text-xs font-medium text-white ${selectedPeer.color}`}>
                  {selectedPeer.initials}
                </div>
                <div>
                  <h1 className="text-base font-medium text-slate-100">{selectedPeer.name}</h1>
                  <p className="text-xs text-slate-400">
                    {peerTransfers.length} {peerTransfers.length > 1 ? 'fichiers' : 'fichier'} dans l'historique
                  </p>
                </div>
              </div>
              <button className="p-2 hover:bg-slate-800 rounded-md text-slate-400 hover:text-slate-200 transition-colors">
                <MoreVertical size={18} />
              </button>
            </header>

            <div className="flex-1 overflow-y-auto p-8 space-y-8">
              {/* Send Action Card */}
              <div className="bg-slate-900 border border-slate-800 rounded-xl p-5 shadow-lg shadow-black/20">
                <h3 className="text-sm font-medium text-slate-200 mb-4">Nouvel envoi</h3>
                <div className="flex flex-wrap items-center gap-3">
                  {/* Recipient Dropdown */}
                  <div className="w-48 bg-slate-950 border border-slate-700/50 hover:border-slate-600 rounded-lg py-2 px-3 text-sm text-slate-300 flex justify-between items-center cursor-pointer transition-colors">
                    <div className="flex items-center gap-2 truncate">
                      <div className={`w-5 h-5 rounded-full flex items-center justify-center text-[9px] font-bold text-white ${selectedPeer.color}`}>
                        {selectedPeer.initials}
                      </div>
                      <span className="truncate">{selectedPeer.name}</span>
                    </div>
                    <ChevronDown size={14} className="text-slate-500" />
                  </div>

                  {/* File Picker */}
                  <div className="flex-1 min-w-[200px] relative">
                    <div className="absolute inset-y-0 left-0 pl-3 flex items-center pointer-events-none">
                      <Paperclip size={16} className="text-slate-500" />
                    </div>
                    <div className="w-full bg-slate-950 border border-slate-700/50 hover:border-slate-600 rounded-lg py-2 pl-10 pr-4 text-sm text-slate-400 cursor-pointer transition-colors flex justify-between items-center group">
                      <span>Sélectionner un fichier...</span>
                      <span className="text-[10px] uppercase font-bold tracking-wider text-slate-600 group-hover:text-slate-500">Parcourir</span>
                    </div>
                  </div>
                  
                  {/* Send Button */}
                  <button className="bg-indigo-600 hover:bg-indigo-500 text-white px-5 py-2 rounded-lg text-sm font-medium shadow-sm transition-all flex items-center gap-2 group shadow-indigo-900/20">
                    <Send size={16} className="group-hover:translate-x-0.5 transition-transform" />
                    Envoyer
                  </button>
                </div>
              </div>

              {/* Transfer History */}
              <div>
                <h3 className="text-xs font-semibold text-slate-500 uppercase tracking-wider mb-4 px-1">Historique des transferts</h3>
                
                {peerTransfers.length > 0 ? (
                  <div className="bg-slate-900/50 border border-slate-800/80 rounded-xl overflow-hidden divide-y divide-slate-800/80">
                    {peerTransfers.map(transfer => (
                      <div key={transfer.id} className="group relative flex items-center p-4 hover:bg-slate-800/50 transition-colors">
                        
                        {/* Type Icon */}
                        <div className="w-10 h-10 rounded-lg bg-slate-800 flex items-center justify-center flex-shrink-0">
                          {getFileIcon(transfer.type)}
                        </div>

                        {/* Details */}
                        <div className="ml-4 flex-1 min-w-0 pr-4">
                          <div className="flex items-center gap-2 mb-1">
                            <span className="font-medium text-slate-200 text-sm truncate">{transfer.filename}</span>
                            {transfer.direction === 'sent' ? (
                              <ArrowUpRight size={14} className="text-indigo-400 flex-shrink-0" />
                            ) : (
                              <ArrowDownLeft size={14} className="text-emerald-400 flex-shrink-0" />
                            )}
                          </div>
                          
                          <div className="flex items-center text-xs text-slate-500 gap-3">
                            <span>{transfer.size}</span>
                            <span className="w-1 h-1 rounded-full bg-slate-700"></span>
                            <span>{transfer.direction === 'sent' ? 'Envoyé' : 'Reçu'} • {transfer.time}</span>
                          </div>

                          {/* Progress Bar (if in progress) */}
                          {transfer.status === 'progress' && (
                            <div className="mt-3 flex items-center gap-3">
                              <div className="h-1.5 flex-1 bg-slate-800 rounded-full overflow-hidden">
                                <div 
                                  className="h-full bg-indigo-500 rounded-full relative overflow-hidden"
                                  style={{ width: `${transfer.progress}%` }}
                                >
                                  <div className="absolute inset-0 bg-white/20 w-full animate-[shimmer_2s_infinite]"></div>
                                </div>
                              </div>
                              <span className="text-[10px] font-medium text-indigo-400 min-w-[2rem] text-right">{transfer.progress}%</span>
                            </div>
                          )}
                        </div>

                        {/* Status / Actions */}
                        <div className="ml-auto flex items-center gap-3">
                          {transfer.status === 'success' && (
                            <div className="flex items-center gap-2">
                              <span className="text-xs font-medium text-emerald-500 bg-emerald-500/10 px-2.5 py-1 rounded-full">Terminé</span>
                              {transfer.direction === 'received' && (
                                <button className="opacity-0 group-hover:opacity-100 p-1.5 text-slate-400 hover:text-slate-200 hover:bg-slate-700 rounded-md transition-all tooltip-trigger relative" title="Ouvrir l'emplacement">
                                  <FolderOpen size={16} />
                                </button>
                              )}
                            </div>
                          )}
                          
                          {transfer.status === 'progress' && (
                            <span className="text-xs font-medium text-indigo-400 bg-indigo-500/10 px-2.5 py-1 rounded-full flex items-center gap-1.5">
                              <span className="w-1.5 h-1.5 rounded-full bg-indigo-500 animate-pulse"></span>
                              En cours
                            </span>
                          )}

                          {transfer.status === 'failed' && (
                            <div className="flex items-center gap-2">
                              <span className="text-xs font-medium text-rose-500 bg-rose-500/10 px-2.5 py-1 rounded-full">Échoué</span>
                              <button className="opacity-0 group-hover:opacity-100 p-1.5 text-slate-400 hover:text-slate-200 hover:bg-slate-700 rounded-md transition-all tooltip-trigger relative" title="Réessayer">
                                <RefreshCw size={16} />
                              </button>
                            </div>
                          )}
                        </div>

                      </div>
                    ))}
                  </div>
                ) : (
                  <div className="flex flex-col items-center justify-center py-16 px-4 text-center bg-slate-900/30 border border-slate-800/50 rounded-xl border-dashed">
                    <div className="w-12 h-12 bg-slate-800 rounded-full flex items-center justify-center mb-4">
                      <File className="text-slate-500" size={24} />
                    </div>
                    <p className="text-sm font-medium text-slate-300">Aucun transfert</p>
                    <p className="text-xs text-slate-500 mt-1 max-w-[240px]">Vous n'avez pas encore échangé de fichiers avec {selectedPeer.name}.</p>
                  </div>
                )}
              </div>
            </div>
          </>
        ) : (
          <div className="flex-1 flex flex-col items-center justify-center p-8">
            <div className="w-16 h-16 bg-slate-900 rounded-2xl flex items-center justify-center mb-6 shadow-inner border border-slate-800">
              <ArrowUpRight size={24} className="text-slate-600" />
            </div>
            <h2 className="text-lg font-medium text-slate-200 mb-2">Sélectionnez un contact</h2>
            <p className="text-sm text-slate-500 max-w-[300px] text-center">Choisissez un pair sur le réseau local dans la barre latérale pour voir l'historique et envoyer des fichiers.</p>
          </div>
        )}
      </main>

      {/* Inline styles for custom animations (shimmer) since we can't edit global css easily without an extra file, but let's use a standard tailwind approach if possible, or add a style tag */}
      <style dangerouslySetInnerHTML={{__html: `
        @keyframes shimmer {
          0% { transform: translateX(-100%); }
          100% { transform: translateX(100%); }
        }
        /* Custom scrollbar for sidebar */
        .custom-scrollbar::-webkit-scrollbar {
          width: 4px;
        }
        .custom-scrollbar::-webkit-scrollbar-track {
          background: transparent;
        }
        .custom-scrollbar::-webkit-scrollbar-thumb {
          background: rgba(148, 163, 184, 0.2);
          border-radius: 4px;
        }
        .custom-scrollbar:hover::-webkit-scrollbar-thumb {
          background: rgba(148, 163, 184, 0.4);
        }
      `}} />
    </div>
  );
}
