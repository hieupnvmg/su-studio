import {Composition} from 'remotion';
import {MapScene, type MapSceneProps, defaultMapProps} from './MapScene';

// Size and length come from the props the app sends, so one composition serves 16:9 and 9:16.
export const Root = () => (
	<Composition
		id="MapScene"
		component={MapScene}
		defaultProps={defaultMapProps}
		fps={30}
		width={1920}
		height={1080}
		durationInFrames={300}
		calculateMetadata={({props}: {props: MapSceneProps}) => ({
			width: props.width,
			height: props.height,
			fps: 30,
			durationInFrames: Math.max(30, Math.round(props.seconds * 30)),
		})}
	/>
);
