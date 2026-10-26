import React, { useState } from "react";
import { Check, Copy, Terminal } from "lucide-react";

interface RichMarkdownProps {
  content: string;
  className?: string;
}

interface TableData {
  headers: string[];
  rows: string[][];
}

interface CodeData {
  language: string;
  code: string;
}

type BlockKind =
  | { type: "h1"; text: string }
  | { type: "h2"; text: string }
  | { type: "h3"; text: string }
  | { type: "bullet"; text: string }
  | { type: "quote"; text: string }
  | { type: "divider" }
  | { type: "table"; data: TableData }
  | { type: "code"; data: CodeData }
  | { type: "paragraph"; text: string };

// Helper to render inline formatting: **bold**, *italic*, `code`, [link](url)
export function renderInlineMarkdown(text: string): React.ReactNode {
  // Tokenize string with regex matching inline elements
  const tokens: React.ReactNode[] = [];
  let remaining = text;
  let key = 0;

  while (remaining.length > 0) {
    // 1. Inline code: `code`
    const codeMatch = remaining.match(/^`([^`]+)`/);
    if (codeMatch) {
      tokens.push(
        <code
          key={key++}
          className="px-1.5 py-0.5 rounded bg-white/10 border border-white/10 font-mono text-[11px] text-indigo-300 mx-0.5"
        >
          {codeMatch[1]}
        </code>
      );
      remaining = remaining.slice(codeMatch[0].length);
      continue;
    }

    // 2. Bold text: **text** or __text__
    const boldMatch = remaining.match(/^(\*\*|__)(.*?)\1/);
    if (boldMatch) {
      tokens.push(
        <strong key={key++} className="font-bold text-white">
          {boldMatch[2]}
        </strong>
      );
      remaining = remaining.slice(boldMatch[0].length);
      continue;
    }

    // 3. Italic text: *text* or _text_
    const italicMatch = remaining.match(/^(\*|_)(.*?)\1/);
    if (italicMatch && !italicMatch[2].startsWith(" ")) {
      tokens.push(
        <em key={key++} className="italic text-white/90">
          {italicMatch[2]}
        </em>
      );
      remaining = remaining.slice(italicMatch[0].length);
      continue;
    }

    // 4. Links: [text](url)
    const linkMatch = remaining.match(/^\[([^\]]+)\]\(([^)]+)\)/);
    if (linkMatch) {
      tokens.push(
        <a
          key={key++}
          href={linkMatch[2]}
          target="_blank"
          rel="noreferrer"
          className="text-indigo-400 hover:text-indigo-300 underline underline-offset-2"
        >
          {linkMatch[1]}
        </a>
      );
      remaining = remaining.slice(linkMatch[0].length);
      continue;
    }

    // Regular character accumulation until next special token
    const nextSpecial = remaining.search(/[`*_\[]/);
    if (nextSpecial === -1) {
      tokens.push(<span key={key++}>{remaining}</span>);
      break;
    } else if (nextSpecial === 0) {
      // Escape or lone character
      tokens.push(<span key={key++}>{remaining[0]}</span>);
      remaining = remaining.slice(1);
    } else {
      tokens.push(<span key={key++}>{remaining.slice(0, nextSpecial)}</span>);
      remaining = remaining.slice(nextSpecial);
    }
  }

  return tokens;
}

export const RichMarkdownDocumentView: React.FC<RichMarkdownProps> = ({
  content,
  className = "",
}) => {
  const blocks: BlockKind[] = [];
  const lines = content.replace(/\r\n/g, "\n").split("\n");

  const parseTableRow = (line: string): string[] => {
    let raw = line.trim();
    if (raw.startsWith("|")) raw = raw.slice(1);
    if (raw.endsWith("|")) raw = raw.slice(0, -1);
    return raw.split("|").map((cell) => cell.trim());
  };

  let i = 0;
  while (i < lines.length) {
    const line = lines[i];
    const trimmed = line.trim();

    if (!trimmed) {
      i++;
      continue;
    }

    // Fenced Code Block: ```lang
    if (trimmed.startsWith("```")) {
      const lang = trimmed.slice(3).trim();
      i++;
      const codeLines: string[] = [];
      while (i < lines.length) {
        const cLine = lines[i];
        if (cLine.trim().startsWith("```")) {
          i++;
          break;
        }
        codeLines.push(cLine);
        i++;
      }
      blocks.push({
        type: "code",
        data: {
          language: lang || "code",
          code: codeLines.join("\n"),
        },
      });
      continue;
    }

    // Markdown Table: | Col 1 | Col 2 | followed by |---|---|
    if (
      trimmed.startsWith("|") &&
      i + 1 < lines.length &&
      lines[i + 1].trim().startsWith("|") &&
      lines[i + 1].trim().includes("-")
    ) {
      const headers = parseTableRow(trimmed);
      i += 2; // skip header and separator row

      const rows: string[][] = [];
      while (i < lines.length) {
        const rLine = lines[i].trim();
        if (rLine.startsWith("|")) {
          rows.push(parseTableRow(rLine));
          i++;
        } else {
          break;
        }
      }
      blocks.push({
        type: "table",
        data: { headers, rows },
      });
      continue;
    }

    // Headings
    if (trimmed.startsWith("# ")) {
      blocks.push({ type: "h1", text: trimmed.slice(2).trim() });
    } else if (trimmed.startsWith("## ")) {
      blocks.push({ type: "h2", text: trimmed.slice(3).trim() });
    } else if (trimmed.startsWith("### ")) {
      blocks.push({ type: "h3", text: trimmed.slice(4).trim() });
    } else if (
      trimmed.startsWith("- ") ||
      trimmed.startsWith("* ") ||
      /^\d+\.\s/.test(trimmed)
    ) {
      const cleanText = trimmed.replace(/^(\d+\.\s|- |\* )/, "");
      blocks.push({ type: "bullet", text: cleanText });
    } else if (trimmed.startsWith("> ")) {
      blocks.push({ type: "quote", text: trimmed.slice(2).trim() });
    } else if (trimmed === "---" || trimmed === "***" || trimmed === "___") {
      blocks.push({ type: "divider" });
    } else {
      blocks.push({ type: "paragraph", text: trimmed });
    }

    i++;
  }

  return (
    <div
      className={`space-y-3 font-sans text-xs text-white/85 leading-relaxed select-text ${className}`}
    >
      {blocks.length === 0 ? (
        <span className="text-white/40 italic">Empty document content</span>
      ) : (
        blocks.map((block, idx) => {
          switch (block.type) {
            case "h1":
              return (
                <h1
                  key={idx}
                  className="text-base font-bold text-white tracking-tight pt-2 border-b border-white/10 pb-1"
                >
                  {renderInlineMarkdown(block.text)}
                </h1>
              );

            case "h2":
              return (
                <h2
                  key={idx}
                  className="text-sm font-bold text-white tracking-tight pt-2.5 text-indigo-200"
                >
                  {renderInlineMarkdown(block.text)}
                </h2>
              );

            case "h3":
              return (
                <h3
                  key={idx}
                  className="text-xs font-semibold text-white/95 pt-1.5"
                >
                  {renderInlineMarkdown(block.text)}
                </h3>
              );

            case "bullet":
              return (
                <div key={idx} className="flex items-start gap-2 pl-2">
                  <span className="text-[#87B996] font-bold text-sm leading-none mt-0.5">
                    •
                  </span>
                  <div className="flex-1">{renderInlineMarkdown(block.text)}</div>
                </div>
              );

            case "quote":
              return (
                <blockquote
                  key={idx}
                  className="border-l-2 border-[#87B996] pl-3 py-1 bg-white/[0.02] text-white/70 italic text-xs my-1"
                >
                  {renderInlineMarkdown(block.text)}
                </blockquote>
              );

            case "divider":
              return <div key={idx} className="h-px bg-white/10 my-2" />;

            case "table":
              return <MarkdownTable key={idx} data={block.data} />;

            case "code":
              return <CodeBlock key={idx} data={block.data} />;

            case "paragraph":
              return (
                <p key={idx} className="text-white/85 leading-relaxed">
                  {renderInlineMarkdown(block.text)}
                </p>
              );

            default:
              return null;
          }
        })
      )}
    </div>
  );
};

// Render Markdown Table
const MarkdownTable: React.FC<{ data: TableData }> = ({ data }) => {
  return (
    <div className="my-2.5 overflow-x-auto rounded-xl border border-white/15 bg-black/40 shadow-sm">
      <table className="w-full text-left text-xs border-collapse">
        <thead>
          <tr className="bg-white/[0.08] border-b border-white/15">
            {data.headers.map((header, hIdx) => (
              <th
                key={hIdx}
                className="px-3 py-2 font-semibold text-white tracking-tight whitespace-nowrap"
              >
                {renderInlineMarkdown(header)}
              </th>
            ))}
          </tr>
        </thead>
        <tbody className="divide-y divide-white/5 font-sans">
          {data.rows.map((row, rIdx) => (
            <tr
              key={rIdx}
              className={`hover:bg-white/[0.03] transition-colors ${
                rIdx % 2 === 1 ? "bg-white/[0.015]" : ""
              }`}
            >
              {data.headers.map((_, cIdx) => (
                <td
                  key={cIdx}
                  className="px-3 py-2 text-white/80 whitespace-normal"
                >
                  {renderInlineMarkdown(row[cIdx] || "")}
                </td>
              ))}
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
};

// Render Code Block with Header & Copy
const CodeBlock: React.FC<{ data: CodeData }> = ({ data }) => {
  const [copied, setCopied] = useState(false);

  const handleCopy = () => {
    navigator.clipboard.writeText(data.code);
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  };

  return (
    <div className="my-2.5 rounded-xl border border-white/15 bg-[#0D0F13] overflow-hidden shadow-md">
      <div className="px-3 py-1.5 bg-white/[0.05] border-b border-white/10 flex items-center justify-between text-[11px]">
        <div className="flex items-center gap-1.5 text-white/60 font-mono font-semibold">
          <Terminal className="w-3 h-3 text-[#87B996]" />
          <span>{data.language.toUpperCase()}</span>
        </div>
        <button
          onClick={handleCopy}
          className="flex items-center gap-1 text-white/50 hover:text-white transition-colors"
        >
          {copied ? (
            <>
              <Check className="w-3 h-3 text-emerald-400" />
              <span className="text-emerald-400 font-medium">Copied</span>
            </>
          ) : (
            <>
              <Copy className="w-3 h-3" />
              <span>Copy</span>
            </>
          )}
        </button>
      </div>
      <pre className="p-3 font-mono text-[11px] text-white/90 overflow-x-auto leading-relaxed whitespace-pre select-text">
        <code>{data.code}</code>
      </pre>
    </div>
  );
};
