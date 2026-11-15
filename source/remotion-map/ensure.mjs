// Downloads the headless Chrome that Remotion renders with (once). Prints JSON progress lines.
import {ensureBrowser} from '@remotion/renderer';

const log = (value) => process.stdout.write(JSON.stringify(value) + '\n');
try {
	await ensureBrowser({
		onBrowserDownload: () => {
			log({phase: 'browser', progress: 0});
			return {version: null, onProgress: ({percent}) => log({phase: 'browser', progress: percent})};
		},
	});
	log({phase: 'done', progress: 1});
} catch (error) {
	log({phase: 'error', message: String(error?.message || error).slice(0, 600)});
	process.exit(1);
}
