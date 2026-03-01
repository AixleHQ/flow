const SELECTED_PROJECT_KEY = 'selected-project-id';

export const getSelectedProjectId = (): string | null => localStorage.getItem(SELECTED_PROJECT_KEY);

export const setSelectedProjectId = (id: string | null) => {
  if (id) {
    localStorage.setItem(SELECTED_PROJECT_KEY, id);
  } else {
    localStorage.removeItem(SELECTED_PROJECT_KEY);
  }
};
