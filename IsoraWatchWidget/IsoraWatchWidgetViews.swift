//
//  IsoraWatchWidgetViews.swift
//  IsoraWatchWidget
//

import SwiftUI
import WidgetKit
import UIKit

/// UI strings, centralized so a later localization pass only touches this file.
enum WidgetStrings {
    static let configurationDisplayName = "Isora"
    static let configurationDescription = String(localized: "Resume what you're currently listening to.")
    static let emptyState = String(localized: "No book")
    static let chapterAbbreviation = String(localized: "ch.")
    static let percentChapterSuffix = String(localized: "% CH.")
    static let separator = " · "
}

struct WatchNowPlayingWidgetView: View {
    let entry: WatchNowPlayingEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if entry.snapshot.title == nil {
            EmptyStateView(family: family)
        } else {
            switch family {
            case .accessoryCircular:
                CircularNowPlayingView(snapshot: entry.snapshot)
            case .accessoryRectangular:
                RectangularNowPlayingView(snapshot: entry.snapshot)
            case .accessoryCorner:
                CornerNowPlayingView(snapshot: entry.snapshot)
            case .accessoryInline:
                InlineNowPlayingView(snapshot: entry.snapshot)
            default:
                RectangularNowPlayingView(snapshot: entry.snapshot)
            }
        }
    }
}

private struct EmptyStateView: View {
    let family: WidgetFamily

    var body: some View {
        switch family {
        case .accessoryInline:
            Label(WidgetStrings.emptyState, systemImage: "waveform")
        case .accessoryCorner:
            Image(systemName: "waveform")
                .widgetLabel(WidgetStrings.emptyState)
        default:
            VStack(spacing: 2) {
                Image(systemName: "waveform")
                    .font(.title3)
                Text(WidgetStrings.emptyState)
                    .font(.caption2)
            }
            .foregroundStyle(.secondary)
        }
    }
}

private struct CircularNowPlayingView: View {
    let snapshot: WatchNowPlayingSnapshot

    var body: some View {
        Gauge(value: Double(snapshot.progressPercent), in: 0...100) {
            Image(systemName: "waveform")
        } currentValueLabel: {
            VStack(spacing: 0) {
                Text(verbatim: "\(snapshot.progressPercent)")
                    .font(.system(.title3, design: .rounded).bold())
                Text(WidgetStrings.percentChapterSuffix)
                    .font(.system(size: 6))
            }
        }
        .gaugeStyle(.accessoryCircular)
        .widgetAccentable()
    }
}

private struct RectangularNowPlayingView: View {
    let snapshot: WatchNowPlayingSnapshot

    var body: some View {
        HStack(spacing: 6) {
            coverView
            VStack(alignment: .leading, spacing: 2) {
                Text(snapshot.title ?? "")
                    .font(.headline)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Gauge(value: Double(snapshot.progressPercent), in: 0...100) {
                    EmptyView()
                }
                .gaugeStyle(.accessoryLinear)
                .widgetAccentable()
            }
        }
    }

    @ViewBuilder
    private var coverView: some View {
        if let data = snapshot.cover, let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 40, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            RoundedRectangle(cornerRadius: 8)
                .fill(.quaternary)
                .frame(width: 40, height: 40)
                .overlay { Image(systemName: "book.closed") }
        }
    }

    private var subtitle: String {
        var parts: [String] = []
        if let number = snapshot.chapterNumber {
            parts.append("\(WidgetStrings.chapterAbbreviation) \(number)")
        }
        parts.append(snapshot.remainingInBook.hoursMinutesFormatted)
        return parts.joined(separator: WidgetStrings.separator)
    }
}

private struct CornerNowPlayingView: View {
    let snapshot: WatchNowPlayingSnapshot

    var body: some View {
        Image(systemName: snapshot.isPlaying ? "play.fill" : "pause.fill")
            .widgetLabel {
                Gauge(value: Double(snapshot.progressPercent), in: 0...100) {
                    EmptyView()
                }
                .gaugeStyle(.accessoryLinearCapacity)
                .widgetAccentable()
            }
    }
}

private struct InlineNowPlayingView: View {
    let snapshot: WatchNowPlayingSnapshot

    var body: some View {
        let chapter = snapshot.chapterNumber.map { "\(WidgetStrings.chapterAbbreviation) \($0)" }
        let parts = [WidgetStrings.configurationDisplayName, chapter, "\(snapshot.progressPercent) %"]
            .compactMap { $0 }
        Text(parts.joined(separator: WidgetStrings.separator))
    }
}
