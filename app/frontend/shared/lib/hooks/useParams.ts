import { useRouter } from '@tanstack/react-router';

export function useParams() {
  const router = useRouter();
  const params = router.state.matches.at(-1)?.params;

  return params;
}
