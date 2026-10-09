import { INVOICE_STATE_LABELS, PP_FLAG_LABELS, PP_SITUATION_LABELS, SD_STAGE_LABELS } from "@raiox/contracts";

const ENUM_LABELS: Record<string, string> = {
  ...PP_SITUATION_LABELS,
  ...PP_FLAG_LABELS,
  ...SD_STAGE_LABELS,
  ...INVOICE_STATE_LABELS,
};

export function enumLabel(value: string): string {
  return ENUM_LABELS[value] ?? value;
}
