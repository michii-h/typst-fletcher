#import "utils.typ": *
#import "marks.typ": *

/// Get the point at which a connector should attach to a node from a given
/// angle, taking into account the node's size and shape.
///
/// - node (dictionary): The node to connect to.
/// - θ (angle): The desired angle from the node's center to the connection
///  point.
/// -> point
// #let get-node-anchor(node, θ) = {

// 	if node.radius < 1e-3pt { return node.real-pos }

// 	if node.shape == "circle" {
// 		vector.add(
// 			node.real-pos,
// 			vector-polar(node.radius + node.outset, θ),
// 		)

// 	} else if node.shape == "rect" {
// 		let origin = node.real-pos

// 		// this is for the "defocus adjustment"
// 		// basically, for very long/wide nodes, don't make edges coming in from
// 		// all angles go to the exact node center, but "spread them out" a bit.
// 		// https://www.desmos.com/calculator/irt0mvixky
// 		let μ = calc.pow(node.aspect, node.defocus)
// 		let origin-δ = (
// 			calc.max(0pt, node.size.at(0)/2*(1 - 1/μ))*calc.cos(θ),
// 			calc.max(0pt, node.size.at(1)/2*(1 - μ/1))*calc.sin(θ),
// 		)
// 		let crossing-line = (
// 			vector.add(origin, origin-δ),
// 			vector.add(origin, vector-polar(1e3*node.radius, θ)),
// 		)

// 		// intersect-rect-with-crossing-line(node.outer-rect, crossing-line)
// 		node.real-pos

// 	} else { panic(node.shape) }
// }

/// Get the points where a connector between two nodes should be drawn between,
/// taking into account the nodes' sizes and relative positions.
///
/// - edge (dictionary): The connector whose end points should be determined.
/// - nodes (pair of dictionaries): The start and end nodes of the connector.
/// -> pair of points
// #let get-edge-anchors(edge, nodes) = {
// 	assert(nodes.len() == 2)
// 	let center-center-line = nodes.map(node => node.real-pos)

// 	let v = vector.sub(..center-center-line)
// 	let θ = vector-angle(v) // approximate angle of connector

// 	if edge.kind in ("line", "arc") {
// 		let δ = edge.bend
// 		let incident-angles = (θ + δ + 180deg, θ - δ)

// 		let points = zip(nodes, incident-angles).map(((node, θ)) => {
// 			get-node-anchor(node, θ)
// 		})

// 		return points
// 	} else if edge.kind == "corner" {

// 		zip(nodes, (θ + 180deg, θ)).map(((node, θ)) => {
// 			get-node-anchor(node, θ)
// 		})
// 	} else { panic(edge) }

// }

#let draw-edge-label(edge, label-pos, options) = {

	cetz.draw.content(
		label-pos,
		box(
			fill: edge.crossing-fill,
			inset: .2em,
			radius: .2em,
			stroke: if options.debug >= 2 { DEBUG_COLOR + 0.25pt },
			[#edge.label],
		),
		anchor: if edge.label-anchor != auto { edge.label-anchor },
	)

	if options.debug >= 2 {
		cetz.draw.circle(
			label-pos,
			radius: 0.75pt,
			stroke: none,
			fill: DEBUG_COLOR,
		)
	}


}

// Get the arrow head adjustment for a given extrusion distance
#let cap-offsets(edge, y) = {
	(0, 1).map(pos => {
		let mark = edge.marks.find(mark => calc.abs(mark.pos - pos) < 1e-3)
		if mark == none { return 0pt }
		let x = cap-offset(mark, (2*pos - 1)*y/edge.stroke.thickness)

		let rev = mark.at("rev", default: false)
		if pos == int(rev) { x -= mark.at("inner-len", default: 0) }
		if rev { x = -x - mark.at("outer-len", default: 0) }
		if pos == 0 { x += mark.at("outer-len", default: 0) }

		x*edge.stroke.thickness
	})
}


#let draw-edge-line(edge, (from, to), options) = {

	// Stroke end points, before adjusting for the arrow head

	let θ = vector-angle(vector.sub(to, from))

	// Draw line(s), one for each extrusion shift
	for shift in edge.extrude {
		// let shifted-line-points = (from, to).zip((0pt, 0pt))
		let shifted-line-points = (from, to).zip(cap-offsets(edge, shift))
			.map(((point, offset)) => vector.add(
				point,
				vector.add(
					// Shift end points lengthways depending on markers
					vector-polar(offset, θ),
					// Shift line sideways (for double line effects, etc)
					vector-polar(shift, θ + 90deg),
				)
			))

		cetz.draw.line(
			..shifted-line-points,
			stroke: edge.stroke,
		)
	}

	// Draw marks
	let curve(t) = vector.lerp(from, to, t)
	for mark in edge.marks {
		place-arrow-cap(curve, edge.stroke, mark, debug: options.debug >= 4)
	}

	// Draw label
	if edge.label != none {

		// Choose label anchor based on connector direction,
		// preferring to place labels above the edge
		if edge.label-side == auto {
			edge.label-side = if calc.abs(θ) < 90deg { left } else { right }
		}

		let label-dir = if edge.label-side == left { +1 } else { -1 }

		if edge.label-anchor == auto {
			edge.label-anchor = angle-to-anchor(θ - label-dir*90deg)
		}

		edge.label-sep = to-abs-length(edge.label-sep, options.em-size)
		let label-pos = vector.add(
			vector.lerp(from, to, edge.label-pos),
			vector-polar(edge.label-sep, θ + label-dir*90deg),
		)
		draw-edge-label(edge, label-pos, options)
	}



}

#let draw-edge-arc(edge, (from, to), options) = {

	// Stroke end points, before adjusting for the arrow heads
	// let (from, to) = get-edge-anchors(edge, nodes)
	let θ = vector-angle(vector.sub(to, from))

	// Determine the arc from the stroke end points and bend angle
	let (center, radius, start, stop) = get-arc-connecting-points(from, to, edge.bend)

	let bend-dir = if edge.bend > 0deg { +1 } else { -1 }

	// Draw arc(s), one for each extrusion shift
	for shift in edge.extrude {

		// Adjust arc angles to accomodate for cap offsets
		let (δ-start, δ-stop) = cap-offsets(edge, shift)
			.map(arclen => -bend-dir*arclen/radius*1rad)

		cetz.draw.arc(
			center,
			radius: radius + shift,
			start: start + δ-start,
			stop: stop + δ-stop,
			anchor: "origin",
			stroke: edge.stroke,
		)
	}


	// Draw marks
	let curve(t) = vector.add(center, vector-polar(radius, lerp(start, stop, t)))
	for mark in edge.marks {
		place-arrow-cap(curve, edge.stroke, mark, debug: options.debug >= 4)
	}


	// Draw label
	if edge.label != none {

		if edge.label-side == auto {
			edge.label-side = if edge.bend > 0deg { left } else { right }
		}
		let label-dir = if edge.label-side == left { +1 } else { -1 }

		if edge.label-anchor == auto {
			// Choose label anchor based on connector direction
			edge.label-anchor = angle-to-anchor(θ - label-dir*90deg)
		}

		edge.label-sep = to-abs-length(edge.label-sep, options.em-size)
		let label-pos = vector.add(
			center,
			vector-polar(
				radius + label-dir*bend-dir*edge.label-sep,
				lerp(start, stop, edge.label-pos),
			)
		)

		draw-edge-label(edge, label-pos, options)
	}


	// Draw debug stuff
	if options.debug >= 3 {
		// for (cell, point) in zip(nodes, (from, to)) {
		// 	cetz.draw.line(
		// 		cell.real-pos,
		// 		point,
		// 		stroke: DEBUG_COLOR + 0.1pt,
		// 	)
		// }

		cetz.draw.arc(
			center,
			radius: radius,
			start: start,
			stop: stop,
			anchor: "origin",
			stroke: DEBUG_COLOR + edge.stroke.thickness/4,
		)

	}


}


#let draw-edge-polyline(edge, (from, to), options) = {

	let verts = (
		from,
		..edge.vertices.map(options.get-coord),
		to,
	)
	let n-segments = verts.len() - 1

	// angles of each segment
	let θs = range(1, verts.len()).map(i => {
		let (vert, vert-next) = (verts.at(i - 1), verts.at(i))
		vector-angle(vector.sub(vert-next, vert))
	})


	// round corners

	// i literally don't know how this works
	let calculate-rounded-corner(i) = {
		let pt = verts.at(i)
		let Δθ = wrap-angle-180(θs.at(i) - θs.at(i - 1))
		let dir = sign(Δθ) // +1 if ccw, -1 if cw

		let θ-normal = θs.at(i - 1) + Δθ/2 + 90deg  // direction to center of curvature

		let radius = edge.corner-radius
		radius *= calc.abs(90deg/Δθ) // visual adjustment so that tighter bends have smaller radii
		radius += if dir > 0 { calc.max(..edge.extrude) } else { -calc.min(..edge.extrude) }
		radius *= dir // ??? makes math easier or something

		let dist = radius/calc.cos(Δθ/2) // distance from vertex to center of curvature

		(
			arc-center: vector.add(pt, vector-polar(dist, θ-normal)),
			arc-radius: radius,
			start: θs.at(i - 1) - 90deg,
			delta: wrap-angle-180(Δθ),
			line-shift: radius*calc.tan(Δθ/2), // distance from vertex to beginning of arc
		)
	}

	let rounded-corners
	if edge.corner-radius != none {
		rounded-corners = if edge.corner-radius != none {
			range(1, θs.len()).map(calculate-rounded-corner)
		}
	}


	if options.debug >= 4 {
		cetz.draw.on-layer(1, cetz.draw.line(
			..verts,
			stroke: 0.1pt + green
		))
	}

	let scaled-label-pos = edge.label-pos*n-segments

	let lerp-scale(t, i) = {
		let τ = t*n-segments - i
		if 0 < τ and τ <= 1 or i == 0 and τ <= 0 or i == n-segments - 1 and 1 < τ { τ }
	}

	for i in range(verts.len() - 1) {
		let (from, to) = (verts.at(i), verts.at(i + 1))
		let marks = ()

		if edge.corner-radius == none {

			// add phantom marks to ensure segment joins are clean
			if i > 0 {
				let Δθ = θs.at(i) - θs.at(i - 1)
				marks.push((
					kind: "bar",
					pos: 0,
					angle: Δθ/2,
					hide: true,
				))
			}
			if i < θs.len() - 1 {
				let Δθ = θs.at(i + 1) - θs.at(i)
				marks.push((
					kind: "bar",
					pos: 1,
					angle: Δθ/2,
					hide: true,
				))
			}
		} else { // rounded corners

			if i > 0 {
				let (line-shift,) = rounded-corners.at(i - 1)
				from = vector.add(from, vector-polar(line-shift, θs.at(i)))
			}

			if i < θs.len() - 1 {
				let (arc-center, arc-radius, start, delta, line-shift) = rounded-corners.at(i)
				to = vector.add(to, vector-polar(-line-shift, θs.at(i)))

				for d in edge.extrude {
					cetz.draw.arc(
						arc-center,
						radius: arc-radius - d,
						start: start,
						delta: delta,
						anchor: "origin",
						stroke: edge.stroke,
					)


					if options.debug >= 4 {
						cetz.draw.on-layer(1, cetz.draw.circle(
							arc-center,
							radius: arc-radius - d,
							stroke: 0.1pt + green,
						))

					}
				}

			}

		}

		// distribute original marks across segments
		marks += edge.marks.map(mark => {
			mark.pos = lerp-scale(mark.pos, i)
			mark
		}).filter(mark => mark.pos != none)

		let label-pos = lerp-scale(edge.label-pos, i)
		if label-pos == none {
			draw-edge-line(edge + (kind: "line", marks: marks, label: none), (from, to), options)
		} else {
			draw-edge-line(edge + (kind: "line", marks: marks, label-pos: label-pos, label: edge.label), (from, to), options)
		}

	}
}




#let draw-node-anchoring-ray(node, θ) = {
	let r = 10*(node.radius + node.outset)

	if node.shape == "circle" {
		cetz.draw.line(
			node.real-pos,
			vector.add(
				node.real-pos,
				vector-polar(r, θ),
			),
		)
	} else {

		// this is for the "defocus adjustment"
		// basically, for very long/wide nodes, don't make edges coming in from
		// all angles go to the exact node center, but "spread them out" a bit.
		// https://www.desmos.com/calculator/irt0mvixky
		let μ = calc.pow(node.aspect, node.defocus)
		let δ = (
			calc.max(0pt, node.size.at(0)/2*(1 - 1/μ))*calc.cos(θ),
			calc.max(0pt, node.size.at(1)/2*(1 - μ/1))*calc.sin(θ),
		)

		cetz.draw.line(
			vector.add(node.real-pos, δ),
			vector.add(node.real-pos, vector-polar(r, θ)),
		)

	}

}

#let draw-edge-connecting-nodes(edge, nodes, angles, drawing-function, options) = {

	let interset-node-outline(i) = {
		let node = nodes.at(i)
		cetz.draw.intersections("anchor-" + str(i), {
			(node.draw)(node, node.outset)
			draw-node-anchoring-ray(node, angles.at(i))
		})
	}

	let anchors = nodes.map(node => {
		// if node is a point, then that's the anchor point for edges
		if node.radius == 0pt { node.real-pos }
	})

	cetz.draw.hide({
		if anchors.at(0) == none {
			interset-node-outline(0)
		}
		if anchors.at(1) == none {
			interset-node-outline(1)
		}
	})

	cetz.draw.get-ctx(ctx => {

		let pts = range(2).map(i => {
			if anchors.at(i) != none {
				anchors.at(i)
			} else {
				let p = (ctx.nodes.at("anchor-" + str(i)).anchors)("0")
				p.at(1) *= -1
				vector-2d(vector.scale(p, 1cm))
			}
		})


		(drawing-function)(edge, pts, options)
	})

}

#let get-node-anchor(node, θ, callback) = {
	if node.radius == 0pt {
		callback(node.real-pos)
	} else {
		// find intersection point of θ-angled ray with node outline
		let ray = draw-node-anchoring-ray(node, θ)
		let outline = (node.draw)(node, node.outset)
		cetz.draw.hide(cetz.draw.intersections("node-anchor", ray + outline))

		cetz.draw.get-ctx(ctx => {

			let anchors = ctx.nodes.node-anchor.anchors
			if anchors(()).len() < 1 { panic("Couldn't get node anchor. Node:", node, "Angle:", θ) }

			let anchor-pt = anchors("0")
			anchor-pt.at(1) *= -1 // dunno why this is needed
			// also not sure where this 1cm comes from
			anchor-pt = vector-2d(vector.scale(anchor-pt, 1cm))

			callback(anchor-pt)
		})

	}
}

#let draw-anchored-line(edge, nodes, options) = {
	let (from, to) = nodes.map(n => n.real-pos)
	let θ = vector-angle(vector.sub(to, from))

	draw-edge-connecting-nodes(
		edge,
		nodes,
		(θ, 180deg + θ),
		draw-edge-line,
		options,
	)

}

#let draw-anchored-arc(edge, nodes, options) = {

	let (from, to) = nodes.map(n => n.real-pos)
	let θ = vector-angle(vector.sub(to, from))

	draw-edge-connecting-nodes(
		edge,
		nodes,
		(θ + edge.bend, 180deg + θ - edge.bend),
		draw-edge-arc,
		options,
	)

}

#let draw-anchored-polyline(edge, nodes, options) = {

	let end-segments = range(2).map(i => (
		(options.get-coord)(edge.vertices.at(-i)),
		nodes.at(i).real-pos,
	))

	draw-edge-connecting-nodes(
		edge,
		nodes,
		(
			vector-angle(vector.sub(..end-segments.at(0))),
			vector-angle(vector.sub(..end-segments.at(1))),
		),
		draw-edge-polyline,
		options,
	)
}

#let draw-anchored-corner(edge, nodes, options) = {

	let (from, to) = nodes.map(n => n.real-pos)
	let θ = vector-angle(vector.sub(to, from))

	let θ-floor = calc.floor(θ/90deg)*90deg
	let θ-ceil = calc.ceil(θ/90deg)*90deg

	let bend-dir = (
		if edge.corner == right { true }
		else if edge.corner == left { false }
		else { panic("Edge corner option must be left or right.") }
	)

	let angles = (
		if bend-dir { (θ-ceil, θ-floor + 180deg) }
		else { (θ-floor, θ-ceil + 180deg) }
	)


	let corner-point = if calc.even(calc.floor(θ/90deg) + int(bend-dir)) {
		(nodes.at(1).pos.at(0), nodes.at(0).pos.at(1))
	} else {
		(nodes.at(0).pos.at(0), nodes.at(1).pos.at(1))
	}

	let edge-options = (
		vertices: (corner-point,),
		label-side: if bend-dir { left } else { right },
	)

	draw-edge-connecting-nodes(
		edge + edge-options,
		nodes,
		angles,
		draw-edge-polyline,
		options,
	)
}

#let draw-edge(edge, nodes, options) = {
	edge.marks = interpret-marks(edge.marks)
	if edge.kind == "line" { draw-anchored-line(edge, nodes, options) }
	else if edge.kind == "arc" { draw-anchored-arc(edge, nodes, options) }
	else if edge.kind == "corner" { draw-anchored-corner(edge, nodes, options) }
	else if edge.kind == "poly" { draw-anchored-polyline(edge, nodes, options) }
	else { panic(edge.kind) }
}



#let draw-node(node, options) = {


	if node.stroke != none or node.fill != none {

		if node.draw == none {
			panic("Node doesn't have `draw` callback set.", node)
		}

		cetz.draw.group({
			for (i, extrude) in node.extrude.enumerate() {
				cetz.draw.set-style(
					fill: if i == 0 { node.fill },
					stroke: node.stroke,
				)
				(node.draw)(node, extrude)
			}

		})
	}

	if node.label != none {
		cetz.draw.content(node.real-pos, node.label, anchor: "center")
	}

	// Draw debug stuff
	if options.debug >= 1 {
		// dot at node anchor
		cetz.draw.circle(
			node.real-pos,
			radius: 0.5pt,
			fill: DEBUG_COLOR,
			stroke: none,
		)
	}

	// Show anchor outline
	if options.debug >= 2 and node.radius != 0pt {
		cetz.draw.group({
			cetz.draw.set-style(
				stroke: DEBUG_COLOR + .1pt,
				fill: none,
			)
			(node.draw)(node, node.outset)
		})
	}

	// // node bounding shapes
	// if options.debug >= 3 and node.shape == "rect" {
	// 	cetz.draw.rect(
	// 		..node.rect,
	// 		stroke: DEBUG_COLOR + 0.25pt,
	// 	)
	// }
	// if options.debug >= 3 and node.shape == "circle" {
	// 	cetz.draw.circle(
	// 		node.real-pos,
	// 		radius: node.radius,
	// 		stroke: DEBUG_COLOR + 0.25pt,
	// 	)
	// }
}


#let draw-debug-axes(grid, options) = {

	// draw axes
	if options.debug >= 1 {

		cetz.draw.scale(
			x: grid.scale.at(0),
			y: grid.scale.at(1),
		)
		// cetz panics if rect is zero area
		if grid.bounding-size.all(x => x != 0pt) {
			cetz.draw.rect(
				(0,0),
				grid.bounding-size,
				stroke: DEBUG_COLOR + 0.25pt
			)
		}

		for (axis, coord) in ((0, (x,y) => (x,y)), (1, (y,x) => (x,y))) {

			for (i, x) in grid.centers.at(axis).enumerate() {
				let size = grid.sizes.at(axis).at(i)

				// coordinate label
				cetz.draw.content(
					coord(x, -.5em),
					// text(fill: DEBUG_COLOR, size: .75em)[#(grid.origin.at(axis) + i)],
					text(fill: DEBUG_COLOR, size: .7em)[#(grid.origin.at(axis) + i)]

					// anchor: if axis == 0 { "south" } else { "east" }
				)

				// size bracket
				cetz.draw.line(
					..(+1, -1).map(dir => coord(x + dir*max(size, 1e-6pt)/2, 0)),
					stroke: DEBUG_COLOR + .75pt,
					mark: (start: "|", end: "|")
				)

				// gridline
				cetz.draw.line(
					coord(x, 0),
					coord(x, grid.bounding-size.at(1 - axis)),
					stroke: (
						paint: DEBUG_COLOR,
						thickness: .3pt,
						dash: "densely-dotted",
					),
				)
			}
		}
	}
}

#let find-node-at(nodes, pos) = {
	nodes.filter(node => node.pos == pos)
		.sorted(key: node => node.radius).last()
}

#let draw-diagram(
	grid,
	nodes,
	edges,
	options,
) = {


	for node in nodes {
		draw-node(node, options)
	}

	for edge in edges {
		let nodes = (edge.from, edge.to).map(find-node-at.with(nodes))
		draw-edge(edge, nodes, options)
	}

	draw-debug-axes(grid, options)

}
