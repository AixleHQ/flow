import { type Driver, driver } from 'driver.js';

import 'driver.js/dist/driver.css';

import classes from './productTour.module.css';

export interface HighlightAction {
  label: string;
  onClick: () => void;
}

/** One popover of the tour: a mask with a cut-out around `element`, or a centred popover without one. */
export interface Highlight {
  element?: Element;
  title: string;
  description: string;
  /** The highlighted element takes clicks; everything else under the mask does not. */
  interactive: boolean;
  /** The primary button (Next, Finish); none on a step the member advances by clicking. */
  primary?: HighlightAction;
  /** Shown left of the primary button; Skip tour is always among them. */
  actions: HighlightAction[];
}

/** What the tour draws with. Driver.js in the app; tests pass a fake. */
export interface TourHighlighter {
  show(highlight: Highlight): void;
  clear(): void;
}

function button(label: string, onClick: () => void, className: string): HTMLButtonElement {
  const element = document.createElement('button');
  element.type = 'button';
  element.textContent = label;
  element.className = className;
  element.addEventListener('click', onClick);
  return element;
}

// Driver.js draws one step at a time here: the step order, page changes and
// progress belong to ProductTourProvider, so the library stays replaceable.
export function createDriverHighlighter(): TourHighlighter {
  let instance: Driver | null = null;

  return {
    show({ element, title, description, interactive, primary, actions }) {
      instance?.destroy();
      instance = driver({
        allowClose: false,
        allowKeyboardControl: false,
        overlayClickBehavior: 'none',
        disableActiveInteraction: !interactive,
        stagePadding: 6,
        stageRadius: 8,
        popoverClass: classes.popover,
        showButtons: [],
        onPopoverRender: (popover) => {
          popover.footer.style.display = 'flex';
          popover.footerButtons.replaceChildren(
            ...actions.map((action) => button(action.label, action.onClick, classes.secondaryButton)),
            ...(primary ? [button(primary.label, primary.onClick, classes.primaryButton)] : []),
          );
        },
      });
      instance.highlight({ element, popover: { title, description } });
    },
    clear() {
      instance?.destroy();
      instance = null;
    },
  };
}
