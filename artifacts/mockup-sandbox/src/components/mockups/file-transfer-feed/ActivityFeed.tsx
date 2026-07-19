import React, { useState, useMemo } from 'react';
import {
  Search,
  Plus,
  Image as ImageIcon,
  FileArchive,
  ArrowUp,
  ArrowDown,
  CheckCircle2,
  XCircle,
  FolderOpen,
  RotateCw,
  Paperclip,
  Send,
  X,
  FileSpreadsheet,
  FileText,
  Clock,
  Inbox
} from 'lucide-react';
import './activity-feed.css';

type TransferStatus = 'done' | 'progress' | 'failed';
type TransferDirection = 'sent' | 'received';

interface Transfer {
  id: string;
  filename: string;
  size: string;
  type: string;
  direction: TransferDirection;
  status: TransferStatus;
  progress?: number;
  peerName: string;
  peerAvatar: string;
  peerColor: string;
  timestamp: string;
  dateGroup: string;
}

const MOCK_DATA: Transfer[] = [
  {
    id: '1',
    filename: 'Budget_2026.xlsx',
    size: '1.2 MB',
    type: 'excel',
    direction: 'received',
    status: 'done',
    peerName: 'Chloé Bernard',
    peerAvatar: 'CB',
    peerColor: 'bg-emerald-100 text-emerald-700',
    timestamp: '14:32',
    dateGroup: 'Aujourd\'hui'
  },
  {
    id: '2',
    filename: 'Logo_v3.png',
    size: '4.5 MB',
    type: 'image',
    direction: 'sent',
    status: 'progress',
    progress: 65,
    peerName: 'Marc Lefèvre',
    peerAvatar: 'ML',
    peerColor: 'bg-blue-100 text-blue-700',
    timestamp: '11:15',
    dateGroup: 'Aujourd\'hui'
  },
  {
    id: '3',
    filename: 'Compte_Rendu_Reunion.pdf',
    size: '850 KB',
    type: 'pdf',
    direction: 'received',
    status: 'failed',
    peerName: 'Sophie Martin',
    peerAvatar: 'SM',
    peerColor: 'bg-purple-100 text-purple-700',
    timestamp: '09:40',
    dateGroup: 'Aujourd\'hui'
  },
  {
    id: '4',
    filename: 'Photos_Team_Building.zip',
    size: '145 MB',
    type: 'zip',
    direction: 'sent',
    status: 'done',
    peerName: 'Lucas Dubois',
    peerAvatar: 'LD',
    peerColor: 'bg-orange-100 text-orange-700',
    timestamp: '16:20',
    dateGroup: 'Hier'
  },
  {
    id: '5',
    filename: 'Design_System_v1.fig',
    size: '22 MB',
    type: 'figma',
    direction: 'received',
    status: 'done',
    peerName: 'Emma Petit',
    peerAvatar: 'EP',
    peerColor: 'bg-pink-100 text-pink-700',
    timestamp: '10:05',
    dateGroup: 'Lundi 14 juillet'
  }
];

const PEERS = ['Chloé Bernard', 'Marc Lefèvre', 'Sophie Martin', 'Lucas Dubois', 'Emma Petit', 'Antoine Roux'];

export function ActivityFeed() {
  const [filter, setFilter] = useState<'all' | 'received' | 'sent' | 'failed'>('all');
  const [search, setSearch] = useState('');
  const [isSendOpen, setIsSendOpen] = useState(false);
  const [selectedFile, setSelectedFile] = useState<File | null>(null);
  const [selectedPeer, setSelectedPeer] = useState<string>('');

  const filteredData = useMemo(() => {
    return MOCK_DATA.filter(t => {
      const matchesSearch = t.filename.toLowerCase().includes(search.toLowerCase()) || 
                            t.peerName.toLowerCase().includes(search.toLowerCase());
      const matchesFilter = filter === 'all' || 
                            (filter === 'received' && t.direction === 'received') ||
                            (filter === 'sent' && t.direction === 'sent') ||
                            (filter === 'failed' && t.status === 'failed');
      return matchesSearch && matchesFilter;
    });
  }, [search, filter]);

  const groupedData = useMemo(() => {
    const groups: Record<string, Transfer[]> = {};
    filteredData.forEach(t => {
      if (!groups[t.dateGroup]) groups[t.dateGroup] = [];
      groups[t.dateGroup].push(t);
    });
    return groups;
  }, [filteredData]);

  const getFileIcon = (type: string) => {
    switch (type) {
      case 'excel': return <FileSpreadsheet className="w-6 h-6 text-emerald-500" />;
      case 'image': return <ImageIcon className="w-6 h-6 text-blue-500" />;
      case 'pdf': return <FileText className="w-6 h-6 text-red-500" />;
      case 'zip': return <FileArchive className="w-6 h-6 text-yellow-600" />;
      default: return <FileText className="w-6 h-6 text-slate-500" />;
    }
  };

  const getFileIconBg = (type: string) => {
    switch (type) {
      case 'excel': return 'bg-emerald-50';
      case 'image': return 'bg-blue-50';
      case 'pdf': return 'bg-red-50';
      case 'zip': return 'bg-yellow-50';
      default: return 'bg-slate-100';
    }
  };

  return (
    <div className="activity-feed-root flex flex-col h-screen max-h-screen bg-slate-50 text-slate-800">
      
      {/* HEADER */}
      <header className="bg-white border-b border-slate-200 px-6 py-4 flex flex-col gap-4 z-10 shadow-sm">
        <div className="flex items-center justify-between">
          <h1 className="text-2xl font-bold text-slate-900 tracking-tight">Transferts</h1>
          <button 
            onClick={() => setIsSendOpen(!isSendOpen)}
            className="flex items-center gap-2 bg-indigo-600 hover:bg-indigo-700 text-white px-4 py-2 rounded-full font-medium transition-colors shadow-sm"
          >
            {isSendOpen ? <X className="w-4 h-4" /> : <Plus className="w-4 h-4" />}
            <span>Envoyer un fichier</span>
          </button>
        </div>

        <div className="flex flex-col sm:flex-row gap-4 items-start sm:items-center justify-between">
          <div className="relative w-full sm:w-72">
            <Search className="w-4 h-4 text-slate-400 absolute left-3 top-1/2 -translate-y-1/2" />
            <input 
              type="text" 
              placeholder="Rechercher un fichier, contact..."
              className="w-full pl-9 pr-4 py-2 bg-slate-100 border-transparent focus:bg-white focus:border-indigo-500 focus:ring-2 focus:ring-indigo-200 rounded-full text-sm outline-none transition-all"
              value={search}
              onChange={(e) => setSearch(e.target.value)}
            />
          </div>
          
          <div className="flex gap-2 overflow-x-auto pb-1 sm:pb-0 w-full sm:w-auto hide-scrollbar">
            {[
              { id: 'all', label: 'Tous' },
              { id: 'received', label: 'Reçus', icon: <ArrowDown className="w-3 h-3" /> },
              { id: 'sent', label: 'Envoyés', icon: <ArrowUp className="w-3 h-3" /> },
              { id: 'failed', label: 'Échoués', icon: <XCircle className="w-3 h-3" /> },
            ].map(f => (
              <button
                key={f.id}
                onClick={() => setFilter(f.id as any)}
                className={`flex items-center gap-1.5 px-3.5 py-1.5 rounded-full text-sm font-semibold transition-colors whitespace-nowrap ${
                  filter === f.id 
                    ? 'bg-indigo-100 text-indigo-700' 
                    : 'bg-slate-100 text-slate-600 hover:bg-slate-200'
                }`}
              >
                {f.icon}
                {f.label}
              </button>
            ))}
          </div>
        </div>
      </header>

      {/* SEND PANEL (Collapsible) */}
      <div 
        className={`bg-white border-b border-slate-200 overflow-hidden transition-all duration-300 ease-in-out ${
          isSendOpen ? 'max-h-64 opacity-100' : 'max-h-0 opacity-0'
        }`}
      >
        <div className="p-6 max-w-3xl mx-auto">
          <div className="flex flex-col sm:flex-row gap-4 items-end">
            <div className="flex-1 w-full flex flex-col gap-1.5">
              <label className="text-sm font-semibold text-slate-700">Sélectionner un fichier</label>
              <div className="border-2 border-dashed border-slate-300 rounded-xl p-4 flex items-center justify-center bg-slate-50 hover:bg-slate-100 transition-colors cursor-pointer group">
                <div className="flex items-center gap-3 text-slate-500 group-hover:text-indigo-600 transition-colors">
                  <Paperclip className="w-5 h-5" />
                  <span className="text-sm font-medium">Parcourir ou glisser-déposer</span>
                </div>
              </div>
            </div>
            
            <div className="flex-1 w-full flex flex-col gap-1.5">
              <label className="text-sm font-semibold text-slate-700">Destinataire</label>
              <select 
                className="w-full px-4 py-3.5 bg-slate-50 border border-slate-200 rounded-xl text-sm outline-none focus:border-indigo-500 focus:ring-2 focus:ring-indigo-200 transition-all appearance-none"
                value={selectedPeer}
                onChange={(e) => setSelectedPeer(e.target.value)}
              >
                <option value="" disabled>Choisir un contact du réseau...</option>
                {PEERS.map(p => <option key={p} value={p}>{p}</option>)}
              </select>
            </div>
            
            <button className="bg-indigo-600 hover:bg-indigo-700 text-white h-[52px] px-6 rounded-xl font-semibold flex items-center gap-2 transition-colors w-full sm:w-auto justify-center shadow-sm">
              <Send className="w-4 h-4" />
              Envoyer
            </button>
          </div>
        </div>
      </div>

      {/* FEED LIST */}
      <main className="flex-1 overflow-y-auto p-4 sm:p-6 lg:p-8">
        <div className="max-w-4xl mx-auto space-y-8">
          
          {Object.keys(groupedData).length === 0 ? (
            <div className="flex flex-col items-center justify-center py-20 text-center">
              <div className="w-32 h-32 bg-indigo-50 rounded-full flex items-center justify-center mb-6">
                <Inbox className="w-12 h-12 text-indigo-300" />
              </div>
              <h3 className="text-xl font-bold text-slate-800 mb-2">Aucun transfert trouvé</h3>
              <p className="text-slate-500 max-w-sm mb-6">
                Vous n'avez pas encore échangé de fichiers ou votre recherche ne donne aucun résultat.
              </p>
              {!isSendOpen && (
                <button 
                  onClick={() => setIsSendOpen(true)}
                  className="bg-indigo-100 text-indigo-700 hover:bg-indigo-200 px-6 py-2.5 rounded-full font-semibold transition-colors"
                >
                  Démarrer un transfert
                </button>
              )}
            </div>
          ) : (
            Object.entries(groupedData).map(([date, transfers]) => (
              <section key={date}>
                <h2 className="text-sm font-bold text-slate-400 uppercase tracking-wider mb-4 flex items-center gap-4">
                  <span>{date}</span>
                  <div className="flex-1 h-px bg-slate-200"></div>
                </h2>
                
                <div className="space-y-3">
                  {transfers.map((t) => (
                    <div 
                      key={t.id} 
                      className={`group relative bg-white border ${t.status === 'progress' ? 'border-indigo-200 shadow-md ring-1 ring-indigo-50' : 'border-slate-200 shadow-sm hover:shadow-md hover:border-slate-300'} rounded-2xl p-4 sm:p-5 transition-all overflow-hidden flex flex-col sm:flex-row sm:items-center gap-4`}
                    >
                      {/* PROGRESS BAR BACKGROUND FOR IN-PROGRESS ITEMS */}
                      {t.status === 'progress' && (
                        <div className="absolute top-0 left-0 h-1 bg-indigo-100 w-full z-0">
                          <div 
                            className="h-full bg-indigo-500 progress-bar-striped transition-all duration-300"
                            style={{ width: `${t.progress}%` }}
                          />
                        </div>
                      )}
                      
                      <div className="relative z-10 flex flex-1 items-center gap-4 min-w-0">
                        {/* FILE ICON */}
                        <div className={`shrink-0 w-12 h-12 rounded-xl flex items-center justify-center ${getFileIconBg(t.type)}`}>
                          {getFileIcon(t.type)}
                        </div>
                        
                        {/* FILE INFO */}
                        <div className="flex flex-col min-w-0 flex-1">
                          <div className="flex items-center gap-2 mb-0.5">
                            <span className="font-bold text-slate-800 truncate" title={t.filename}>{t.filename}</span>
                            {t.direction === 'received' ? (
                              <span className="shrink-0 flex items-center gap-1 text-[10px] uppercase font-bold tracking-wider text-emerald-600 bg-emerald-50 px-2 py-0.5 rounded-full">
                                <ArrowDown className="w-3 h-3" /> Reçu
                              </span>
                            ) : (
                              <span className="shrink-0 flex items-center gap-1 text-[10px] uppercase font-bold tracking-wider text-indigo-600 bg-indigo-50 px-2 py-0.5 rounded-full">
                                <ArrowUp className="w-3 h-3" /> Envoyé
                              </span>
                            )}
                          </div>
                          <div className="flex items-center gap-3 text-sm text-slate-500">
                            <span className="font-medium">{t.size}</span>
                            <span className="w-1 h-1 bg-slate-300 rounded-full"></span>
                            
                            {/* PEER INFO */}
                            <div className="flex items-center gap-1.5 truncate">
                              <div className={`w-5 h-5 rounded-full flex items-center justify-center text-[10px] font-bold ${t.peerColor}`}>
                                {t.peerAvatar}
                              </div>
                              <span className="truncate">{t.peerName}</span>
                            </div>
                          </div>
                        </div>
                      </div>

                      {/* STATUS & ACTIONS */}
                      <div className="relative z-10 flex items-center justify-between sm:justify-end gap-6 sm:w-48 shrink-0 border-t sm:border-t-0 pt-3 sm:pt-0 border-slate-100">
                        
                        <div className="flex items-center gap-2 text-sm">
                          {t.status === 'done' && (
                            <span className="flex items-center gap-1.5 text-slate-500 font-medium">
                              <CheckCircle2 className="w-4 h-4 text-emerald-500" />
                              Terminé
                            </span>
                          )}
                          {t.status === 'failed' && (
                            <span className="flex items-center gap-1.5 text-red-600 font-bold">
                              <XCircle className="w-4 h-4" />
                              Échoué
                            </span>
                          )}
                          {t.status === 'progress' && (
                            <span className="flex items-center gap-1.5 text-indigo-600 font-bold">
                              <RotateCw className="w-4 h-4 animate-spin" />
                              {t.progress}%
                            </span>
                          )}
                        </div>

                        <div className="flex items-center gap-4 text-slate-400 font-medium text-sm">
                          {t.timestamp}
                        </div>

                        {/* HOVER ACTIONS (Desktop) */}
                        <div className="absolute right-0 bg-white/95 backdrop-blur-sm pl-4 flex items-center gap-2 opacity-0 translate-x-4 group-hover:opacity-100 group-hover:translate-x-0 transition-all duration-200">
                          {t.status === 'done' && (
                            <button className="flex items-center gap-1.5 text-sm font-semibold text-slate-600 hover:text-indigo-600 bg-slate-100 hover:bg-indigo-50 px-3 py-1.5 rounded-lg transition-colors" title="Ouvrir le dossier">
                              <FolderOpen className="w-4 h-4" />
                              <span className="hidden sm:inline">Dossier</span>
                            </button>
                          )}
                          {t.status === 'failed' && (
                            <button className="flex items-center gap-1.5 text-sm font-semibold text-white bg-slate-800 hover:bg-slate-900 px-3 py-1.5 rounded-lg transition-colors">
                              <RotateCw className="w-4 h-4" />
                              Réessayer
                            </button>
                          )}
                        </div>
                      </div>
                      
                    </div>
                  ))}
                </div>
              </section>
            ))
          )}

        </div>
      </main>
      
    </div>
  );
}
