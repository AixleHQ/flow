import { useDispatch } from 'react-redux';

import type { AppDispatch } from 'shared/api';

export const useAppDispatch = () => useDispatch<AppDispatch>();
