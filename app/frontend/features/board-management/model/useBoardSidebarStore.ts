import { create } from 'zustand';

import type { BoardTask } from 'entities/board-task';

interface BoardSidebarState {
  isOpen: boolean;
  activeTaskId: number | null;
  activeTab: string;
  openTask: (task: BoardTask | number) => void;
  close: () => void;
  setTab: (tab: string) => void;
}

export const useBoardSidebarStore = create<BoardSidebarState>((set) => ({
  isOpen: false,
  activeTaskId: null,
  activeTab: 'details',

  openTask: (taskOrId) =>
    set({
      isOpen: true,
      activeTaskId: typeof taskOrId === 'number' ? taskOrId : taskOrId.id,
      activeTab: 'details',
    }),

  close: () => set({ isOpen: false, activeTaskId: null }),

  setTab: (tab) => set({ activeTab: tab }),
}));
