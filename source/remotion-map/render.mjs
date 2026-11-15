// Renders the MapScene composition. Usage: node render.mjs video|still <props.json> <output> [frame]
// Prints one JSON object per line ({phase, progress} or {phase:"error", message}) for Sử Studio to follow.
import fs from 'node:fs';
import path from 'node:path';
import {bundle} from '@remotion/bundler';
import {renderMedia, renderStill, selectComposition} from '@remotion/renderer';

const log = (value) => process.stdout.write(JSON.stringify(value) + '\n');
const [, , mode, propsFile, output, frameArg] = process.argv;
try {
	const inputProps = JSON.parse(fs.readFileSync(propsFile, 'utf8'));
	const chromiumOptions = {gl: 'angle'};
	log({phase: 'bundle', progress: 0});
	const serveUrl = await bundle({entryPoint: path.resolve('src/index.ts'), onProgress: (p) => log({phase: 'bundle', progress: p / 100})});
	const composition = await selectComposition({serveUrl, id: 'MapScene', inputProps, chromiumOptions, timeoutInMilliseconds: 120000});
	if (mode === 'still') {
		await renderStill({composition, serveUrl, output, inputProps, frame: Math.min(composition.durationInFrames - 1, Number(frameArg) || 0), chromiumOptions, timeoutInMilliseconds: 120000});
	} else {
		await renderMedia({composition, serveUrl, codec: 'h264', outputLocation: output, inputProps, concurrency: 1, chromiumOptions, timeoutInMilliseconds: 120000, onProgress: ({progress}) => log({phase: 'render', progress})});
	}
	log({phase: 'done', progress: 1});
} catch (error) {
	log({phase: 'error', message: String(error?.message || error).slice(0, 600)});
	process.exit(1);
}
