export const providesListTag = <R extends { id: string | number }[], CacheTag, Params extends Record<string, unknown>>(
  resultsWithIds: R | undefined,
  tagType: CacheTag,
  params: Params,
) => {
  return resultsWithIds
    ? [{ type: tagType, id: 'LIST', ...params }, ...resultsWithIds.map(({ id }) => ({ type: tagType, id, ...params }))]
    : [{ type: tagType, id: 'LIST', ...params }];
};
