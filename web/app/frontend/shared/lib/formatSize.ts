export const formatSize = (size: number): string => {
  if (size >= 1_073_741_824) return (size / 1_073_741_824).toFixed(2) + ' GB';
  if (size >= 1_048_576) return (size / 1_048_576).toFixed(2) + ' MB';
  if (size >= 1024) return (size / 1024).toFixed(2) + ' KB';
  return size + ' B';
};
