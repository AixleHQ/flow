import {
  DndContext,
  DragEndEvent,
  KeyboardSensor,
  PointerSensor,
  closestCenter,
  useSensor,
  useSensors,
} from '@dnd-kit/core';
import {
  SortableContext,
  sortableKeyboardCoordinates,
  useSortable,
  verticalListSortingStrategy,
} from '@dnd-kit/sortable';
import { CSS } from '@dnd-kit/utilities';
import { Tooltip } from '@mantine/core';
import { IconGripVertical, IconPlus, IconTrash } from '@tabler/icons-react';
import { useRef, useState } from 'react';

import classes from './BuilderPage.module.css';

interface SubStep {
  id: number;
  name: string;
  position: number;
}

interface Step {
  id: number;
  name: string;
  position: number;
  allowNonInteractive: boolean;
  bmadEnabled: boolean;
  dependsOnStepIds: number[];
  subSteps: SubStep[];
}

type SelectionMode = 'session' | 'step';
export interface Selection {
  mode: SelectionMode;
  sessionId: number;
  stepId?: number;
}

interface SessionTagsProps {
  step: Step;
  allSteps: Step[];
}

function SessionTags({ step, allSteps }: SessionTagsProps) {
  const tags: { label: string; className: string; tooltip: string; dot?: boolean }[] = [];

  if (step.allowNonInteractive) {
    tags.push({ label: 'AUTO', className: classes.tagAuto, tooltip: 'Runs automatically without approval' });
  }
  if (step.bmadEnabled) {
    tags.push({ label: 'BMAD', className: classes.tagNeutral, tooltip: 'BMAD methodology enabled', dot: true });
  }
  if (step.dependsOnStepIds.length === 0) {
    tags.push({
      label: 'ROOT',
      className: classes.tagNeutral,
      tooltip: 'No dependencies — runs in parallel',
      dot: false,
    });
  } else {
    const firstName = allSteps.find((s) => s.id === step.dependsOnStepIds[0])?.name ?? String(step.dependsOnStepIds[0]);
    const label =
      step.dependsOnStepIds.length === 1 ? `↳ AFTER ${firstName}` : `↳ AFTER ${step.dependsOnStepIds.length} sessions`;
    const tooltipText = `Runs after ${allSteps
      .filter((s) => step.dependsOnStepIds.includes(s.id))
      .map((s) => s.name)
      .join(', ')}`;
    tags.push({ label, className: classes.tagNeutral, tooltip: tooltipText, dot: false });
  }

  return (
    <div className={classes.tagRow}>
      {tags.map((t, i) => (
        <Tooltip key={i} label={t.tooltip} withArrow position="right">
          <span className={`${classes.tag} ${t.className}`}>
            {t.dot && (
              <span
                style={{
                  width: 4,
                  height: 4,
                  borderRadius: '50%',
                  background: 'var(--text-3)',
                  display: 'inline-block',
                  marginRight: 5,
                  flexShrink: 0,
                }}
              />
            )}
            {t.label}
          </span>
        </Tooltip>
      ))}
    </div>
  );
}

interface SortableStepRowProps {
  step: SubStep;
  index: number;
  isSelected: boolean;
  onSelect: () => void;
  onDelete: () => void;
  readOnly: boolean;
}

function SortableStepRow({ step, index, isSelected, onSelect, onDelete, readOnly }: SortableStepRowProps) {
  const { attributes, listeners, setNodeRef, transform, transition, isDragging } = useSortable({
    id: step.id,
    disabled: readOnly,
  });

  const style = {
    transform: CSS.Transform.toString(transform),
    transition,
    opacity: isDragging ? 0.4 : 1,
  };

  const letter = String.fromCharCode(97 + index);

  return (
    <div
      ref={setNodeRef}
      style={style}
      className={`${classes.stepRow} ${isSelected ? classes.stepRowSelected : ''}`}
      onClick={onSelect}
    >
      {!readOnly && (
        <span
          className={classes.dragHandle}
          {...attributes}
          {...listeners}
          aria-label="Drag to reorder step"
          title="Drag to reorder step"
        >
          <IconGripVertical size={12} />
        </span>
      )}
      <span className={`${classes.stepBadge} ${isSelected ? classes.stepBadgeActive : ''}`}>{letter}</span>
      <span
        style={{
          flex: 1,
          fontSize: 13,
          color: isSelected ? 'var(--accent-text)' : 'var(--text-2)',
          overflow: 'hidden',
          textOverflow: 'ellipsis',
          whiteSpace: 'nowrap',
        }}
      >
        {step.name || 'Untitled'}
      </span>
      {!readOnly && (
        <button
          className={classes.rowTrash}
          onClick={(e) => {
            e.stopPropagation();
            onDelete();
          }}
          aria-label={`Delete step "${step.name || 'Untitled'}"`}
          title={`Delete step "${step.name || 'Untitled'}"`}
        >
          <IconTrash size={12} />
        </button>
      )}
    </div>
  );
}

interface SortableSessionRowProps {
  step: Step;
  index: number;
  selection: Selection | null;
  allSteps: Step[];
  onSelectSession: (id: number) => void;
  onSelectStep: (sessionId: number, stepId: number) => void;
  onDeleteSession: (id: number) => void;
  onDeleteStep: (sessionId: number, stepId: number) => void;
  onAddStep: (sessionId: number, stepName: string) => void;
  onReorderSteps: (sessionId: number, oldIndex: number, newIndex: number) => void;
  readOnly: boolean;
}

function SortableSessionRow({
  step,
  index,
  selection,
  allSteps,
  onSelectSession,
  onSelectStep,
  onDeleteSession,
  onDeleteStep,
  onAddStep,
  onReorderSteps,
  readOnly,
}: SortableSessionRowProps) {
  const { attributes, listeners, setNodeRef, transform, transition, isDragging } = useSortable({
    id: step.id,
    disabled: readOnly,
  });

  const style = {
    transform: CSS.Transform.toString(transform),
    transition,
    opacity: isDragging ? 0.4 : 1,
  };

  const isSessionActive = selection?.sessionId === step.id && selection.mode === 'session';

  const sensors = useSensors(
    useSensor(PointerSensor),
    useSensor(KeyboardSensor, { coordinateGetter: sortableKeyboardCoordinates }),
  );

  const handleStepDragEnd = (event: DragEndEvent) => {
    const { active, over } = event;
    if (!over || active.id === over.id) return;
    const sortedSubSteps = [...step.subSteps].sort((a, b) => a.position - b.position);
    const oldIdx = sortedSubSteps.findIndex((ss) => ss.id === active.id);
    const newIdx = sortedSubSteps.findIndex((ss) => ss.id === over.id);
    if (oldIdx !== -1 && newIdx !== -1) {
      onReorderSteps(step.id, oldIdx, newIdx);
    }
  };

  const sortedSubSteps = [...step.subSteps].sort((a, b) => a.position - b.position);

  return (
    <div ref={setNodeRef} style={style}>
      {/* Session row */}
      <div
        className={`${classes.sessionRow} ${isSessionActive ? classes.sessionRowActive : ''}`}
        onClick={() => onSelectSession(step.id)}
      >
        {!readOnly && (
          <span
            className={`${classes.dragHandle} ${classes.sessionDragHandle}`}
            {...attributes}
            {...listeners}
            aria-label={`Drag to reorder session "${step.name || 'Untitled'}"`}
            title={`Drag to reorder session "${step.name || 'Untitled'}"`}
          >
            <IconGripVertical size={14} />
          </span>
        )}
        <span className={`${classes.sessionBadge} ${isSessionActive ? classes.sessionBadgeActive : ''}`}>
          {index + 1}
        </span>
        <div style={{ flex: 1, minWidth: 0 }}>
          <div
            style={{
              fontSize: 14,
              fontWeight: 500,
              color: isSessionActive ? 'var(--accent-text)' : 'var(--text-1)',
              overflow: 'hidden',
              textOverflow: 'ellipsis',
              whiteSpace: 'nowrap',
              marginBottom: 2,
            }}
          >
            {step.name || 'Untitled'}
          </div>
          <SessionTags step={step} allSteps={allSteps} />
        </div>
        {!readOnly && (
          <button
            className={classes.rowTrash}
            onClick={(e) => {
              e.stopPropagation();
              onDeleteSession(step.id);
            }}
            aria-label={`Delete session "${step.name || 'Untitled'}"`}
            title={`Delete session "${step.name || 'Untitled'}"`}
          >
            <IconTrash size={14} />
          </button>
        )}
      </div>

      {/* Nested step rows */}
      {sortedSubSteps.length > 0 && (
        <div className={classes.stepsNested}>
          <DndContext sensors={sensors} collisionDetection={closestCenter} onDragEnd={handleStepDragEnd}>
            <SortableContext items={sortedSubSteps.map((ss) => ss.id)} strategy={verticalListSortingStrategy}>
              {sortedSubSteps.map((ss, ssIdx) => {
                const isStepActive =
                  selection?.mode === 'step' && selection.sessionId === step.id && selection.stepId === ss.id;
                return (
                  <SortableStepRow
                    key={ss.id}
                    step={ss}
                    index={ssIdx}
                    isSelected={isStepActive}
                    onSelect={() => onSelectStep(step.id, ss.id)}
                    onDelete={() => onDeleteStep(step.id, ss.id)}
                    readOnly={readOnly}
                  />
                );
              })}
            </SortableContext>
          </DndContext>
        </div>
      )}

      {/* Per-session "Add a step…" ghost row */}
      {!readOnly && <AddStepGhost sessionId={step.id} onAdd={onAddStep} />}
    </div>
  );
}

interface AddStepGhostProps {
  sessionId: number;
  onAdd: (sessionId: number, stepName: string) => void;
}

function AddStepGhost({ sessionId, onAdd }: AddStepGhostProps) {
  const [editing, setEditing] = useState(false);
  const [value, setValue] = useState('');
  const inputRef = useRef<HTMLInputElement>(null);

  const handleClick = () => {
    setEditing(true);
    setTimeout(() => inputRef.current?.focus(), 0);
  };

  const handleConfirm = () => {
    if (value.trim()) {
      onAdd(sessionId, value.trim());
    }
    setEditing(false);
    setValue('');
  };

  const handleKeyDown = (e: React.KeyboardEvent) => {
    if (e.key === 'Enter') handleConfirm();
    if (e.key === 'Escape') {
      setEditing(false);
      setValue('');
    }
  };

  if (editing) {
    return (
      <div className={`${classes.ghostRowEditing} ${classes.ghostRowStep}`}>
        <input
          ref={inputRef}
          className={classes.ghostInput}
          placeholder="Step name…"
          value={value}
          onChange={(e) => setValue(e.currentTarget.value)}
          onKeyDown={handleKeyDown}
          onBlur={() => {
            setEditing(false);
            setValue('');
          }}
        />
        <span className={classes.ghostHint}>↵ · esc</span>
      </div>
    );
  }

  return (
    <div className={`${classes.ghostRow} ${classes.ghostRowStep}`} onClick={handleClick}>
      <IconPlus size={10} />
      Add a step…
    </div>
  );
}

interface AddSessionGhostProps {
  onAdd: (name: string) => void;
}

function AddSessionGhost({ onAdd }: AddSessionGhostProps) {
  const [editing, setEditing] = useState(false);
  const [value, setValue] = useState('');
  const inputRef = useRef<HTMLInputElement>(null);

  const handleClick = () => {
    setEditing(true);
    setTimeout(() => inputRef.current?.focus(), 0);
  };

  const handleConfirm = () => {
    if (value.trim()) {
      onAdd(value.trim());
    }
    setEditing(false);
    setValue('');
  };

  const handleKeyDown = (e: React.KeyboardEvent) => {
    if (e.key === 'Enter') handleConfirm();
    if (e.key === 'Escape') {
      setEditing(false);
      setValue('');
    }
  };

  if (editing) {
    return (
      <div className={classes.ghostRowEditing}>
        <input
          ref={inputRef}
          className={classes.ghostInput}
          placeholder="Session name…"
          aria-label="Session name"
          value={value}
          onChange={(e) => setValue(e.currentTarget.value)}
          onKeyDown={handleKeyDown}
          onBlur={() => {
            setEditing(false);
            setValue('');
          }}
        />
        <span className={classes.ghostHint}>↵ confirm · esc cancel</span>
      </div>
    );
  }

  return (
    <div className={`${classes.ghostRow} ${classes.ghostRowSession}`} onClick={handleClick}>
      <IconPlus size={12} />
      Add a session…
    </div>
  );
}

interface SessionTreeNavProps {
  steps: Step[];
  selection: Selection | null;
  readOnly: boolean;
  onSelectSession: (id: number) => void;
  onSelectStep: (sessionId: number, stepId: number) => void;
  onDeleteSession: (id: number) => void;
  onDeleteStep: (sessionId: number, stepId: number) => void;
  onAddSession: (name: string) => void;
  onAddStep: (sessionId: number, stepName: string) => void;
  onReorderSessions: (oldIndex: number, newIndex: number) => void;
  onReorderSteps: (sessionId: number, oldIndex: number, newIndex: number) => void;
}

export function SessionTreeNav({
  steps,
  selection,
  readOnly,
  onSelectSession,
  onSelectStep,
  onDeleteSession,
  onDeleteStep,
  onAddSession,
  onAddStep,
  onReorderSessions,
  onReorderSteps,
}: SessionTreeNavProps) {
  const sortedSteps = [...steps].sort((a, b) => a.position - b.position);

  const sensors = useSensors(
    useSensor(PointerSensor),
    useSensor(KeyboardSensor, { coordinateGetter: sortableKeyboardCoordinates }),
  );

  const handleDragEnd = (event: DragEndEvent) => {
    const { active, over } = event;
    if (!over || active.id === over.id) return;
    const oldIdx = sortedSteps.findIndex((s) => s.id === active.id);
    const newIdx = sortedSteps.findIndex((s) => s.id === over.id);
    if (oldIdx !== -1 && newIdx !== -1) {
      onReorderSessions(oldIdx, newIdx);
    }
  };

  return (
    <div className={classes.treeNav}>
      <DndContext sensors={sensors} collisionDetection={closestCenter} onDragEnd={handleDragEnd}>
        <SortableContext items={sortedSteps.map((s) => s.id)} strategy={verticalListSortingStrategy}>
          {sortedSteps.map((step, idx) => (
            <SortableSessionRow
              key={step.id}
              step={step}
              index={idx}
              selection={selection}
              allSteps={sortedSteps}
              onSelectSession={onSelectSession}
              onSelectStep={onSelectStep}
              onDeleteSession={onDeleteSession}
              onDeleteStep={onDeleteStep}
              onAddStep={onAddStep}
              onReorderSteps={onReorderSteps}
              readOnly={readOnly}
            />
          ))}
        </SortableContext>
      </DndContext>

      {/* Global "Add a session…" ghost row */}
      {!readOnly && <AddSessionGhost onAdd={onAddSession} />}
    </div>
  );
}
