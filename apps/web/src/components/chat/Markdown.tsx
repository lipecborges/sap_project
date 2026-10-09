import ReactMarkdown from "react-markdown";
import remarkGfm from "remark-gfm";
import { localizeDates } from "../../lib/utils";

export function Markdown({ text }: { text: string }) {
  return (
    <div className="prose-chat">
      <ReactMarkdown remarkPlugins={[remarkGfm]}>{localizeDates(text)}</ReactMarkdown>
    </div>
  );
}
