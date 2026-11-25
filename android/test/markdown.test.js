// 正文 Markdown 渲染：各语法解析为对应结构而非字面标记；HTML 不渲染。
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { renderBody } from '../src/lib/markdown.js';

const body = (...texts) => ({ paragraphs: texts.map((text) => ({ segments: [{ type: 'text', text }] })) });

test('一期里同时出现多种语法', () => {
  const html = renderBody(
    body('## 小标题', '- 一\n- 二', '1. 甲\n2. 乙', '**粗体** *斜体* `code`', '> 引用', '```\nlet a = 1;\n  缩进\n```'),
  );
  for (const tag of ['<h2>小标题</h2>', '<ul>', '<ol>', '<strong>粗体</strong>', '<em>斜体</em>', '<code>code</code>', '<blockquote>', '<pre><code>let a = 1;\n  缩进\n</code></pre>']) {
    assert.ok(html.includes(tag), `missing ${tag}\n${html}`);
  }
  assert.ok(!/##|\*\*|```/.test(html));
});

test('链接片段可点且交给系统浏览器', () => {
  const html = renderBody({ paragraphs: [{ segments: [{ type: 'text', text: '看 ' }, { type: 'link', text: '这条', url: 'https://e.test/a' }] }] });
  assert.ok(html.includes('<a href="https://e.test/a" target="_blank" rel="noopener noreferrer">这条</a>'), html);
});

test('正文里的 HTML 按文字转义，不渲染', () => {
  const html = renderBody(body('<script>alert(1)</script> <b>x</b>'));
  assert.ok(!html.includes('<script>') && !html.includes('<b>'), html);
});
