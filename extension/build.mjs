import { build } from 'esbuild';
import { mkdir, copyFile } from 'node:fs/promises';
await mkdir('dist', { recursive: true });
for (const entry of ['background', 'content', 'popup']) await build({entryPoints:[`src/${entry}.ts`],outfile:`dist/${entry}.js`,bundle:true,target:'chrome116',format:'iife',sourcemap:true});
for (const file of ['manifest.json','popup.html','popup.css']) await copyFile(file,`dist/${file}`);
