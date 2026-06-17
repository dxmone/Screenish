//
//  FlowLayout.swift
//  Screenish
//
//  Left-to-right layout that wraps subviews onto a new row when they run out of
//  horizontal space, like text reflow. The editor toolbar uses it so its wide
//  control set (14 tools + style controls + actions) wraps to a second row
//  instead of overflowing past the window edge when contextual controls appear.
//

import SwiftUI

struct FlowLayout: Layout {
    var hSpacing: CGFloat = 4
    var vSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        let rows = arrange(subviews: subviews, maxWidth: maxWidth)
        let height = rows.map(\.height).reduce(0, +)
            + vSpacing * CGFloat(max(0, rows.count - 1))
        let width = proposal.width ?? (rows.map(\.width).max() ?? 0)
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize,
                       subviews: Subviews, cache: inout Void) {
        let rows = arrange(subviews: subviews, maxWidth: bounds.width)
        var y = bounds.minY
        for row in rows {
            var x = bounds.minX
            for item in row.items {
                // Center each item vertically within its row so buttons and
                // dividers of differing heights line up.
                let yOffset = (row.height - item.size.height) / 2
                subviews[item.index].place(
                    at: CGPoint(x: x, y: y + yOffset),
                    proposal: ProposedViewSize(item.size))
                x += item.size.width + hSpacing
            }
            y += row.height + vSpacing
        }
    }

    // MARK: - Row packing

    private struct Row {
        var items: [(index: Int, size: CGSize)] = []
        var width: CGFloat = 0
        var height: CGFloat = 0

        mutating func append(index: Int, size: CGSize, hSpacing: CGFloat) {
            if !items.isEmpty { width += hSpacing }
            width += size.width
            height = max(height, size.height)
            items.append((index, size))
        }
    }

    private func arrange(subviews: Subviews, maxWidth: CGFloat) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let projected = current.items.isEmpty
                ? size.width
                : current.width + hSpacing + size.width
            if !current.items.isEmpty && projected > maxWidth {
                rows.append(current)
                current = Row()
            }
            current.append(index: index, size: size, hSpacing: hSpacing)
        }
        if !current.items.isEmpty { rows.append(current) }
        return rows
    }
}
