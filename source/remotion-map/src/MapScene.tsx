import {useEffect, useMemo, useRef, useState} from 'react';
import {AbsoluteFill, Easing, interpolate, useCurrentFrame, useDelayRender, useVideoConfig} from 'remotion';
import * as maplibregl from 'maplibre-gl';
import 'maplibre-gl/dist/maplibre-gl.css';

// Coordinates are [longitude, latitude], as in GeoJSON.
export type LngLat = [number, number];
export type View = {center: LngLat; zoom: number};
export type Side = {id: string; name: string; color: string};
export type Place = {name: string; at: LngLat; kind?: 'city' | 'fort' | 'river' | 'mountain'};
export type Move = {side: string; path: LngLat[]; start: number; end: number; label?: string; kind?: 'advance' | 'retreat'; icon?: 'arrow' | 'ship'};
export type Clash = {at: LngLat; time: number; label?: string};
export type MapSceneProps = {
	/** Seconds over which the camera travels from start to end (set by autoFrame). */
	cameraFrom?: number;
	cameraTo?: number;
	/** Frame the camera from the drawn features instead of the given start/end views (default on). */
	autoFrame?: boolean;
	width: number;
	height: number;
	seconds: number;
	title?: string;
	date?: string;
	style: 'vintage' | 'plain';
	start: View;
	end: View;
	sides: Side[];
	places: Place[];
	moves: Move[];
	clashes: Clash[];
};

export const defaultMapProps: MapSceneProps = {
	width: 1920,
	height: 1080,
	seconds: 10,
	title: 'Chiến dịch Điện Biên Phủ',
	date: '13/3 – 7/5/1954',
	style: 'vintage',
	start: {center: [103.4, 21.6], zoom: 7},
	end: {center: [103.02, 21.39], zoom: 8},
	sides: [
		{id: 'vn', name: 'Quân đội nhân dân Việt Nam', color: '#c0392b'},
		{id: 'fr', name: 'Quân Pháp', color: '#2c5aa0'},
	],
	places: [
		{name: 'Điện Biên Phủ', at: [103.02, 21.39], kind: 'fort'},
		{name: 'Tuần Giáo', at: [103.42, 21.59], kind: 'city'},
		{name: 'Sông Nậm Rốm', at: [103.0, 21.5], kind: 'river'},
	],
	moves: [{side: 'vn', path: [[103.42, 21.59], [103.25, 21.5], [103.06, 21.42]], start: 1, end: 6, label: 'Hành quân vây hãm'}],
	clashes: [{at: [103.02, 21.39], time: 6.5, label: 'Him Lam'}],
};

// Web Mercator at MapLibre's 512 px tiles.
const worldSize = (zoom: number) => 512 * 2 ** zoom;
const project = ([lng, lat]: LngLat, zoom: number): [number, number] => {
	const size = worldSize(zoom), s = Math.sin((Math.max(-85, Math.min(85, lat)) * Math.PI) / 180);
	return [((lng + 180) / 360) * size, (0.5 - Math.log((1 + s) / (1 - s)) / (4 * Math.PI)) * size];
};
const unproject = ([x, y]: [number, number], zoom: number): LngLat => {
	const size = worldSize(zoom);
	return [(x / size) * 360 - 180, (Math.atan(Math.sinh(Math.PI * (1 - (2 * y) / size))) * 180) / Math.PI];
};

/** Screen area left for the map content: below the title, above the legend (and Shorts captions). */
export const safeArea = (width: number, height: number) => {
	const u = Math.min(width, height) / 1080, vertical = height > width;
	return {top: 190 * u, bottom: height - (vertical ? 420 : 150) * u, left: 60 * u, right: width - 60 * u};
};

/** Start and end camera views fitted to the features: everything at first, then the decisive points. */
export const autoFrame = (p: MapSceneProps): {start: View; end: View; cameraFrom?: number; cameraTo?: number} => {
	const all: LngLat[] = [...p.places.map((x) => x.at), ...p.moves.flatMap((m) => m.path), ...p.clashes.map((c) => c.at)];
	if (!all.length) return {start: p.start, end: p.end};
	const area = safeArea(p.width, p.height);
	const fit = (points: LngLat[], fill: number, maxZoom: number): View => {
		const xy = points.map((q) => project(q, 0));
		const [minX, maxX, minY, maxY] = [Math.min(...xy.map((q) => q[0])), Math.max(...xy.map((q) => q[0])), Math.min(...xy.map((q) => q[1])), Math.max(...xy.map((q) => q[1]))];
		const w = (area.right - area.left) * fill, h = (area.bottom - area.top) * fill;
		const zoom = Math.max(1.5, Math.min(maxZoom, Math.log2(Math.min(w / Math.max(maxX - minX, 1e-9), h / Math.max(maxY - minY, 1e-9)))));
		// Put the content centre in the middle of the safe area, not of the whole frame.
		const s = 2 ** zoom, cx = (minX + maxX) / 2, cy = (minY + maxY) / 2;
		const shiftX = (p.width / 2 - (area.left + area.right) / 2) / s, shiftY = (p.height / 2 - (area.top + area.bottom) / 2) / s;
		return {center: unproject([cx + shiftX, cy + shiftY], 0), zoom};
	};
	const start = fit(all, 0.78, 12);
	const lastMoves = p.moves.filter((m) => m.end >= p.seconds * 0.55);
	// Close in on the late action but keep its whole routes in view, at most 1.2 zoom levels closer.
	const focus: LngLat[] = [...p.clashes.filter((c) => c.time >= p.seconds * 0.4).map((c) => c.at), ...lastMoves.flatMap((m) => m.path)];
	let end = focus.length > 1 ? fit(focus, 0.8, start.zoom + 1.2) : {center: focus[0] || start.center, zoom: start.zoom + 0.8};
	if (end.zoom < start.zoom) end = {center: end.center, zoom: start.zoom};
	// Hold the overview until the late action begins, then close in while it plays out.
	const lateClashes = p.clashes.filter((c) => c.time >= p.seconds * 0.4);
	const from = Math.min(...lastMoves.map((m) => m.start), ...lateClashes.map((c) => c.time - 0.5), p.seconds * 0.5);
	const to = Math.max(...lastMoves.map((m) => m.end), ...lateClashes.map((c) => c.time + 0.3), from + 1);
	return {start, end, cameraFrom: Math.max(p.seconds * 0.08, from), cameraTo: Math.min(p.seconds * 0.95, Math.max(to, from + 1))};
};

/** One fixed map image covering both camera views at the sharper zoom (≤ 4096 px per side). */
export const mapPlate = (p: MapSceneProps) => {
	const rect = (v: View, base: number) => {
		const [x, y] = project(v.center, base), s = 2 ** (base - v.zoom);
		return [x - (p.width * s) / 2, y - (p.height * s) / 2, x + (p.width * s) / 2, y + (p.height * s) / 2];
	};
	const bounds = (base: number) => {
		const a = rect(p.start, base), b = rect(p.end, base);
		return [Math.min(a[0], b[0]), Math.min(a[1], b[1]), Math.max(a[2], b[2]), Math.max(a[3], b[3])];
	};
	let base = Math.max(p.start.zoom, p.end.zoom);
	let [l, t, r, b] = bounds(base);
	const shrink = Math.max(1, (r - l) / 4096, (b - t) / 4096);
	if (shrink > 1) {
		base -= Math.log2(shrink);
		[l, t, r, b] = bounds(base);
	}
	return {base, left: l, top: t, width: Math.ceil(r - l), height: Math.ceil(b - t), center: unproject([(l + r) / 2, (t + b) / 2], base)};
};

// Historical look: relief, water, rivers and woods only. No modern roads, buildings, borders or labels.
const mapStyle = (style: MapSceneProps['style']): maplibregl.StyleSpecification => {
	const vintage = style === 'vintage';
	// Elevation tint (lowland → highland) and hillshade from open terrain tiles, so valleys and ranges read at every zoom.
	const tint = vintage
		? [0, '#efe6cb', 150, '#e9ddb9', 500, '#ddcca2', 1000, '#cfb68b', 1600, '#bfa078', 2400, '#ab8a66']
		: [0, '#e7eedb', 150, '#dfe8c9', 500, '#d3dcb1', 1000, '#c9c79b', 1600, '#bfae86', 2400, '#ad9878'];
	return {
		version: 8,
		sources: {
			omt: {type: 'vector', url: 'https://tiles.openfreemap.org/planet'},
			dem: {type: 'raster-dem', tiles: ['https://s3.amazonaws.com/elevation-tiles-prod/terrarium/{z}/{x}/{y}.png'], encoding: 'terrarium', tileSize: 256, maxzoom: 14},
		},
		layers: [
			{id: 'paper', type: 'background', paint: {'background-color': vintage ? '#eadfc4' : '#eef0ea'}},
			{id: 'relief-tint', type: 'color-relief', source: 'dem', paint: {'color-relief-color': ['interpolate', ['linear'], ['elevation'], ...tint], 'color-relief-opacity': 0.9}} as maplibregl.LayerSpecification,
			{id: 'hillshade', type: 'hillshade', source: 'dem', paint: {'hillshade-exaggeration': 0.55, 'hillshade-shadow-color': vintage ? '#4b3d28' : '#45503f', 'hillshade-highlight-color': vintage ? '#fff8e6' : '#ffffff', 'hillshade-accent-color': vintage ? '#7a6545' : '#5f6b55', 'hillshade-illumination-direction': 315}},
			{id: 'wood', type: 'fill', source: 'omt', 'source-layer': 'landcover', filter: ['==', ['get', 'class'], 'wood'], paint: {'fill-color': vintage ? '#9da57a' : '#a9c48f', 'fill-opacity': 0.12}},
			{id: 'water', type: 'fill', source: 'omt', 'source-layer': 'water', paint: {'fill-color': vintage ? '#9fb8b6' : '#a8c8de'}},
			{id: 'river', type: 'line', source: 'omt', 'source-layer': 'waterway', filter: ['in', ['get', 'class'], ['literal', ['river', 'stream']]], paint: {'line-color': vintage ? '#7c9d9d' : '#8fb5d3', 'line-width': ['interpolate', ['linear'], ['zoom'], 5, 0.7, 9, 2.2, 12, 4]}},
		],
	};
};

const clamp = (v: number) => Math.max(0, Math.min(1, v));
const ease = Easing.bezier(0.45, 0, 0.25, 1);

/** Catmull-Rom spline through the points, sampled densely, so marching routes curve naturally. */
export const smoothPath = (points: [number, number][], samples = 14): [number, number][] => {
	if (points.length < 3) return points;
	const out: [number, number][] = [];
	for (let i = 0; i < points.length - 1; i++) {
		const p0 = points[Math.max(0, i - 1)], p1 = points[i], p2 = points[i + 1], p3 = points[Math.min(points.length - 1, i + 2)];
		for (let s = 0; s < samples; s++) {
			const t = s / samples, t2 = t * t, t3 = t2 * t;
			const f = (a: number, b: number, c: number, d: number) => 0.5 * (2 * b + (-a + c) * t + (2 * a - 5 * b + 4 * c - d) * t2 + (-a + 3 * b - 3 * c + d) * t3);
			out.push([f(p0[0], p1[0], p2[0], p3[0]), f(p0[1], p1[1], p2[1], p3[1])]);
		}
	}
	out.push(points[points.length - 1]);
	return out;
};

/** The first `fraction` of a polyline and the direction at its tip. */
export const partialPath = (points: [number, number][], fraction: number) => {
	const lengths = points.slice(1).map((pt, i) => Math.hypot(pt[0] - points[i][0], pt[1] - points[i][1]));
	const total = lengths.reduce((a, b) => a + b, 0);
	let left = total * clamp(fraction);
	const out: [number, number][] = [points[0]];
	let angle = lengths.length ? Math.atan2(points[1][1] - points[0][1], points[1][0] - points[0][0]) : 0;
	for (let i = 0; i < lengths.length && left > 0; i++) {
		const [a, b] = [points[i], points[i + 1]], k = Math.min(1, left / (lengths[i] || 1));
		angle = Math.atan2(b[1] - a[1], b[0] - a[0]);
		out.push([a[0] + (b[0] - a[0]) * k, a[1] + (b[1] - a[1]) * k]);
		left -= lengths[i];
	}
	return {points: out, angle, total};
};

/** Label offsets (in label-height units) that avoid overlapping earlier labels: below, above, right, left. */
export const placeLabels = (points: [number, number][], texts: string[], size: number) => {
	const boxes: [number, number, number, number][] = [];
	return points.map(([x, y], i) => {
		const w = texts[i].length * size * 0.6, h = size * 1.25, side = w / 2 / size + 0.8;
		if (!texts[i]) return [0, 1.4] as [number, number];
		const options: [number, number][] = [[0, 1.4], [0, -0.9], [side, 0.35], [-side, 0.35], [0, 2.7], [0, -2.2], [side, 1.6], [-side, 1.6], [side, -0.9], [-side, -0.9]];
		const fits = ([dx, dy]: [number, number]) => {
			const cx = x + dx * size, cy = y + dy * size, box: [number, number, number, number] = [cx - w / 2, cy - h, cx + w / 2, cy + h * 0.2];
			return boxes.every((b) => box[2] < b[0] || box[0] > b[2] || box[3] < b[1] || box[1] > b[3]) ? box : null;
		};
		const chosen = options.find((o) => fits(o)) || options[0];
		const cx = x + chosen[0] * size, cy = y + chosen[1] * size;
		boxes.push([cx - w / 2, cy - h, cx + w / 2, cy + h * 0.2]);
		return chosen;
	});
};

/** A steamship side view (bow pointing right, about 2 × 1 units, waterline at y = 0.2). */
const ShipGlyph = ({color}: {color: string}) => (
	<g strokeLinejoin="round">
		<path d="M -1.05 -0.05 L 1.1 -0.05 L 0.78 0.3 L -0.9 0.3 Z" fill="#2b2216" stroke="#f6efdc" strokeWidth={0.06} />
		<rect x={-0.62} y={-0.32} width={1.08} height={0.27} fill="#efe4c8" stroke="#2b2216" strokeWidth={0.05} />
		<rect x={-0.28} y={-0.72} width={0.2} height={0.4} fill={color} stroke="#2b2216" strokeWidth={0.05} />
		<rect x={0.08} y={-0.66} width={0.2} height={0.34} fill={color} stroke="#2b2216" strokeWidth={0.05} />
		<line x1={-0.85} y1={-0.05} x2={-0.85} y2={-0.62} stroke="#2b2216" strokeWidth={0.05} />
		<line x1={0.88} y1={-0.05} x2={0.88} y2={-0.5} stroke="#2b2216" strokeWidth={0.05} />
		<circle cx={-0.18} cy={-0.95} r={0.14} fill="#9a8f7c" opacity={0.6} />
		<circle cx={-0.42} cy={-1.12} r={0.11} fill="#9a8f7c" opacity={0.4} />
	</g>
);

export const MapScene = (input: MapSceneProps) => {
	const props = useMemo(() => (input.autoFrame === false ? input : {...input, ...autoFrame(input)}), [input]);
	const frame = useCurrentFrame();
	const {fps, width, height, durationInFrames} = useVideoConfig();
	const {delayRender, continueRender} = useDelayRender();
	const containerRef = useRef<HTMLDivElement>(null);
	const [handle] = useState(() => delayRender('Đang tải bản đồ'));
	const plate = useMemo(() => mapPlate({...props, width, height}), [props, width, height]);

	useEffect(() => {
		if (!containerRef.current) return;
		maplibregl.setWorkerUrl(URL.createObjectURL(new Blob([`import "https://unpkg.com/maplibre-gl@${maplibregl.getVersion()}/dist/maplibre-gl-worker.mjs";`], {type: 'text/javascript'})));
		const map = new maplibregl.Map({
			container: containerRef.current,
			style: mapStyle(props.style),
			center: plate.center,
			zoom: plate.base,
			interactive: false,
			attributionControl: false,
			fadeDuration: 0,
			canvasContextAttributes: {preserveDrawingBuffer: true},
		});
		map.on('load', () => {
			map.jumpTo({center: plate.center, zoom: plate.base});
			map.once('idle', () => continueRender(handle));
		});
	}, [continueRender, handle, plate, props.style]);

	const seconds = frame / fps;
	// Hold the opening and closing views; ease between them.
	const camFrom = props.cameraFrom != null ? props.cameraFrom * fps : durationInFrames * 0.08, camTo = props.cameraTo != null ? props.cameraTo * fps : durationInFrames * 0.92;
	const progress = interpolate(frame, [camFrom, Math.max(camFrom + 1, camTo)], [0, 1], {extrapolateLeft: 'clamp', extrapolateRight: 'clamp', easing: ease});
	const [sx, sy] = project(props.start.center, plate.base), [ex, ey] = project(props.end.center, plate.base);
	const zoom = props.start.zoom + (props.end.zoom - props.start.zoom) * progress;
	const scale = 2 ** (zoom - plate.base), k = 1 / scale, u = Math.min(width, height) / 1080;
	const cx = sx + (ex - sx) * progress - plate.left, cy = sy + (ey - sy) * progress - plate.top;
	const transform = `translate(${width / 2 - cx * scale}px, ${height / 2 - cy * scale}px) scale(${scale})`;
	const at = (p: LngLat): [number, number] => {
		const [x, y] = project(p, plate.base);
		return [x - plate.left, y - plate.top];
	};
	const sideColor = (id: string) => props.sides.find((s) => s.id === id)?.color || '#333333';
	const font = "'Helvetica Neue', Arial, sans-serif";
	const label = (x: number, y: number, text: string, size: number, color = '#1f1a12', italic = false) => (
		<text x={x} y={y} fontSize={size * u * k} fontFamily={font} fontWeight={700} fontStyle={italic ? 'italic' : 'normal'} fill={color} stroke="#f6efdc" strokeWidth={6 * u * k} paintOrder="stroke" textAnchor="middle">{text}</text>
	);
	// Lay labels out at the closest view; at wider views crowded labels are hidden frame by frame (below).
	const labelSize = (30 * u) / 2 ** (Math.max(props.start.zoom, props.end.zoom) - plate.base);
	const offsets = useMemo(
		() => placeLabels(
			[...props.places.map((pl) => at(pl.at)), ...props.clashes.map((c) => at(c.at)), ...props.moves.map((m) => at(m.path[0]))],
			[...props.places.map((pl) => pl.name), ...props.clashes.map((c) => c.label || ''), ...props.moves.map((m) => m.label || '')],
			labelSize,
		),
		[props.places, props.clashes, props.moves, labelSize, plate],
	);
	// A route that runs back along an earlier one (pulling out, retreating) is drawn dashed and beside it.
	const retreats = useMemo(() => {
		const near = (a: LngLat, b: LngLat) => Math.hypot(...([0, 1].map((j) => at(a)[j] - at(b)[j]) as [number, number])) < labelSize;
		return props.moves.map((m, i) => m.kind === 'retreat' || props.moves.slice(0, i).some((o) => near(o.path[0], m.path[m.path.length - 1]) && near(o.path[o.path.length - 1], m.path[0])));
	}, [props.moves, labelSize, plate]);
	const progressOf = (m: Move) => ease(clamp((seconds - m.start) / Math.max(0.1, m.end - m.start)));

	// Every label in one layer, in priority order; a label that would overlap one already shown waits.
	type Label = {x: number; y: number; ax: number; ay: number; text: string; size: number; color: string; italic?: boolean; opacity: number};
	const candidates: Label[] = [];
	props.places.forEach((pl, i) => {
		const [x, y] = at(pl.at), river = pl.kind === 'river', o = river ? [0, 0] : offsets[i];
		candidates.push({x: x + o[0] * 30 * u * k, y: y + o[1] * 30 * u * k, ax: x, ay: y, text: pl.name, size: river ? 26 : 30, color: river ? '#2f5d68' : '#1f1a12', italic: river, opacity: clamp((seconds - 0.2 - i * 0.15) / 0.5)});
	});
	props.clashes.forEach((c, i) => {
		const [x, y] = at(c.at), o = offsets[props.places.length + i];
		if (c.label && seconds >= c.time) candidates.push({x: x + o[0] * 30 * u * k, y: y + o[1] * 30 * u * k, ax: x, ay: y, text: c.label, size: 30, color: '#a04000', opacity: clamp((seconds - c.time) / 0.3)});
	});
	props.moves.forEach((m, i) => {
		const p = progressOf(m), [x, y] = at(m.path[0]), o = offsets[props.places.length + props.clashes.length + i];
		if (m.label && p > 0.15) candidates.push({x: x + o[0] * 30 * u * k, y: y + o[1] * 30 * u * k, ax: x, ay: y, text: m.label, size: 26, color: sideColor(m.side), opacity: clamp((p - 0.15) / 0.2)});
	});
	const shown: number[][] = [];
	const labels = candidates.filter((c) => {
		if (c.opacity <= 0) return false;
		const w = c.text.length * c.size * u * k * 0.58, h = c.size * u * k * 1.15;
		// A label whose point is off screen is hidden (never dragged away from its place); one whose text
		// overflows an edge is nudged inside. Positions are plate units; screen = plate × scale + offset.
		const ox = width / 2 - cx * scale, oy = height / 2 - cy * scale, half = w / 2 + 18 * u * k;
		const sx = c.ax * scale + ox, sy = c.ay * scale + oy;
		if (sx < 0 || sx > width || sy < 0 || sy > height) return false;
		const nudged = Math.min(Math.max(c.x, (0 - ox) / scale + half), (width - ox) / scale - half);
		if (Math.abs(nudged - c.x) > w / 2) return false;
		c.x = nudged;
		const box = [c.x - w / 2, c.y - h, c.x + w / 2, c.y + h * 0.25];
		if (shown.some((b) => !(box[2] < b[0] || box[0] > b[2] || box[3] < b[1] || box[1] > b[3]))) return false;
		shown.push(box);
		return true;
	});

	return (
		<AbsoluteFill style={{backgroundColor: props.style === 'vintage' ? '#eadfc4' : '#eef0ea', overflow: 'hidden'}}>
			<div style={{position: 'absolute', width: plate.width, height: plate.height, transform, transformOrigin: '0 0'}}>
				<div ref={containerRef} style={{position: 'absolute', width: plate.width, height: plate.height, filter: props.style === 'vintage' ? 'sepia(0.2) saturate(0.9) contrast(1.04)' : 'none'}} />
				<svg width={plate.width} height={plate.height} style={{position: 'absolute', left: 0, top: 0, overflow: 'visible'}}>
					{props.moves.map((m, i) => {
						const p = progressOf(m);
						if (p <= 0) return null;
						let dense = smoothPath(m.path.map(at));
						if (retreats[i]) {
							// Shift sideways by a constant screen distance so both routes stay visible.
							const shift = 16 * u * k;
							dense = dense.map((q, j) => {
								const a = dense[Math.max(0, j - 1)], b = dense[Math.min(dense.length - 1, j + 1)], len = Math.hypot(b[0] - a[0], b[1] - a[1]) || 1;
								return [q[0] - ((b[1] - a[1]) / len) * shift, q[1] + ((b[0] - a[0]) / len) * shift] as [number, number];
							});
						}
						const path = partialPath(dense, p), d = path.points.map((q, j) => (j ? 'L' : 'M') + q[0] + ' ' + q[1]).join(' ');
						const tip = path.points[path.points.length - 1], head = 34 * u * k, color = sideColor(m.side);
						const arrow = [[head, 0], [-head * 0.6, head * 0.62], [-head * 0.6, -head * 0.62]].map(([x, y]) => [tip[0] + x * Math.cos(path.angle) - y * Math.sin(path.angle), tip[1] + x * Math.sin(path.angle) + y * Math.cos(path.angle)]);
						const ship = m.icon === 'ship';
						// One ship per voyage: a finished leg hands its ship over to the next leg of the same side.
						const continued = ship && props.moves.some((o, j) => j !== i && o.icon === 'ship' && o.side === m.side && Math.abs(o.end - m.start) <= 0.05);
						const handedOver = ship && p >= 1 && props.moves.some((o, j) => j !== i && o.icon === 'ship' && o.side === m.side && o.start >= m.end - 0.05 && seconds >= o.start);
						const start = path.points[0], dash = ship ? `${3 * u * k} ${14 * u * k}` : retreats[i] ? `${24 * u * k} ${14 * u * k}` : undefined;
						// Finished routes step back so the newest action stands out.
						const after = seconds - m.end, opacity = after > 1 ? Math.max(0.5, 1 - ((after - 1) / 0.8) * 0.5) : 1;
						return (
							<g key={'m' + i} opacity={opacity}>
								{ship ? (
									<path d={d} fill="none" stroke={color} strokeWidth={7 * u * k} strokeLinecap="round" strokeLinejoin="round" strokeDasharray={dash} />
								) : (
									<>
										<path d={d} fill="none" stroke="#1f1a12" strokeOpacity={0.55} strokeWidth={18 * u * k} strokeLinecap={dash ? 'butt' : 'round'} strokeLinejoin="round" strokeDasharray={dash} />
										<path d={d} fill="none" stroke={color} strokeWidth={11 * u * k} strokeLinecap={dash ? 'butt' : 'round'} strokeLinejoin="round" strokeDasharray={dash} />
									</>
								)}
								{continued ? null : <circle cx={start[0]} cy={start[1]} r={10 * u * k} fill={color} stroke="#1f1a12" strokeOpacity={0.55} strokeWidth={3 * u * k} />}
								{ship && handedOver ? null : ship ? (
									// The ship stays upright and faces its direction of travel; a light wake trails behind.
									<g transform={`translate(${tip[0]} ${tip[1]}) scale(${(Math.cos(path.angle) < 0 ? -1 : 1) * 46 * u * k} ${46 * u * k}) rotate(${(Math.cos(path.angle) < 0 ? -1 : 1) * Math.max(-18, Math.min(18, (Math.atan(Math.tan(path.angle)) * 180) / Math.PI))}) translate(0 ${-0.1 + 0.04 * Math.sin(seconds * 5)})`}>
										<path d="M -1.6 0.32 Q -1.25 0.18 -0.95 0.3 M -1.9 0.42 Q -1.5 0.26 -1.05 0.38" fill="none" stroke="#f6efdc" strokeWidth={0.07} strokeLinecap="round" opacity={0.85} />
										<ShipGlyph color={color} />
									</g>
								) : (
									<polygon points={arrow.map((q) => q.join(',')).join(' ')} fill={color} stroke="#1f1a12" strokeOpacity={0.55} strokeWidth={3 * u * k} strokeLinejoin="round" />
								)}
							</g>
						);
					})}
					{props.places.map((pl, i) => {
						const [x, y] = at(pl.at), r = 9 * u * k;
						if (pl.kind === 'river') return null;
						return (
							<g key={'p' + i} opacity={clamp((seconds - 0.2 - i * 0.15) / 0.5)}>
								{pl.kind === 'fort' ? <rect x={x - r} y={y - r} width={2 * r} height={2 * r} fill="#1f1a12" stroke="#f6efdc" strokeWidth={3 * u * k} /> : pl.kind === 'mountain' ? <polygon points={`${x},${y - r * 1.4} ${x - r * 1.3},${y + r} ${x + r * 1.3},${y + r}`} fill="#5b4a32" stroke="#f6efdc" strokeWidth={3 * u * k} /> : <circle cx={x} cy={y} r={r} fill="#1f1a12" stroke="#f6efdc" strokeWidth={3 * u * k} />}
							</g>
						);
					})}
					{props.clashes.map((c, i) => {
						const age = seconds - c.time;
						if (age < 0) return null;
						const [x, y] = at(c.at), pop = clamp(age / 0.3), s = 30 * u * k * (0.6 + 0.4 * pop);
						return (
							<g key={'c' + i}>
								<circle cx={x} cy={y} r={(24 + age * 160) * u * k} fill="none" stroke="#d35400" strokeWidth={6 * u * k} opacity={clamp(1 - age)} />
								<g stroke="#1f1a12" strokeWidth={7 * u * k} strokeLinecap="round" opacity={pop}>
									<line x1={x - s} y1={y - s} x2={x + s} y2={y + s} />
									<line x1={x + s} y1={y - s} x2={x - s} y2={y + s} />
								</g>
								<g stroke="#e67e22" strokeWidth={4 * u * k} strokeLinecap="round" opacity={pop}>
									<line x1={x - s} y1={y - s} x2={x + s} y2={y + s} />
									<line x1={x + s} y1={y - s} x2={x - s} y2={y + s} />
								</g>
							</g>
						);
					})}
					{labels.map((l, i) => <g key={'l' + i} opacity={l.opacity}>{label(l.x, l.y, l.text, l.size, l.color, l.italic)}</g>)}
				</svg>
			</div>
			{props.style === 'vintage' ? <AbsoluteFill style={{background: 'radial-gradient(ellipse at center, rgba(0,0,0,0) 55%, rgba(60,40,15,0.38) 100%)'}} /> : null}
			{props.title || props.date ? (
				<div style={{position: 'absolute', top: (44 - 12 * (1 - clamp(seconds / 0.6))) * u, left: 0, right: 0, display: 'flex', justifyContent: 'center', opacity: clamp(seconds / 0.6)}}>
					<div style={{background: 'rgba(31,26,18,0.82)', color: '#f6efdc', padding: `${12 * u}px ${30 * u}px`, borderRadius: 10 * u, fontFamily: font, textAlign: 'center', maxWidth: width * 0.86}}>
						{props.title ? <div style={{fontSize: 46 * u, fontWeight: 800, lineHeight: 1.2}}>{props.title}</div> : null}
						{props.date ? <div style={{fontSize: 30 * u, opacity: 0.85, marginTop: 4 * u}}>{props.date}</div> : null}
					</div>
				</div>
			) : null}
			{props.sides.length ? (
				<div style={{position: 'absolute', left: 36 * u, bottom: (height > width ? 330 : 40) * u, background: 'rgba(246,239,220,0.88)', padding: `${10 * u}px ${16 * u}px`, borderRadius: 8 * u, fontFamily: font, fontSize: 26 * u, color: '#1f1a12'}}>
					{props.sides.map((s) => (
						<div key={s.id} style={{display: 'flex', alignItems: 'center', gap: 10 * u, margin: `${4 * u}px 0`}}>
							<span style={{width: 34 * u, height: 10 * u, background: s.color, borderRadius: 3 * u, display: 'inline-block'}} />
							{s.name}
						</div>
					))}
				</div>
			) : null}
			<div style={{position: 'absolute', right: 14 * u, bottom: 10 * u, fontFamily: font, fontSize: 15 * u, color: '#3d3526', opacity: 0.8}}>OpenFreeMap © OpenMapTiles · Dữ liệu © OpenStreetMap · Địa hình: SRTM, GMTED2010 (USGS), ETOPO1 (NOAA)</div>
		</AbsoluteFill>
	);
};
