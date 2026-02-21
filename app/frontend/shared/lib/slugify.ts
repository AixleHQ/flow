export const slugify = (str: string) => {
  return str.toLowerCase().replace(/[\s.]/g, '-').replace(/-+/g, '-');
};
