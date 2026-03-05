import { createConsumer, type Consumer } from '@rails/actioncable';

let sharedConsumer: Consumer | null = null;

export function getConsumer(): Consumer {
  if (!sharedConsumer) {
    sharedConsumer = createConsumer();
  }
  return sharedConsumer;
}
