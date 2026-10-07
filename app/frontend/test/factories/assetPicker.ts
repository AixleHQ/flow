import type AssetPicker from '@/types/generated/AssetPicker';

// `name` is the picker name (`folder/name`); `fileName` the bare name, as AssetPickerResource sends them.
export const buildAssetPicker = (overrides: Partial<AssetPicker> = {}): AssetPicker => {
  const folder = overrides.folder ?? null;
  const fileName = overrides.fileName ?? overrides.name?.split('/').pop() ?? 'brand-guide.pdf';
  return {
    id: 31,
    name: folder ? `${folder}/${fileName}` : fileName,
    folder,
    fileName,
    scope: 'project',
    ...overrides,
  };
};
