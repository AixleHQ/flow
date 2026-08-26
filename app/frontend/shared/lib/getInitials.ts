// "Acme Robotics" -> "AR"; single word -> first letter; empty -> "U".
export const getInitials = (name: string): string => {
  const parts = name.trim().split(/\s+/).filter(Boolean);
  if (parts.length === 0) return 'U';
  if (parts.length === 1) return (parts[0][0] ?? 'U').toUpperCase();
  return ((parts[0][0] ?? 'U') + (parts[parts.length - 1][0] ?? 'U')).toUpperCase();
};
