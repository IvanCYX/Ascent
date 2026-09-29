import SwiftUI
#if os(iOS)
import UIKit
#endif

extension View {
    /// Swipe left to reveal Delete, like `List.swipeActions` but for rows inside a `ScrollView` band.
    /// A long press keeps the same action in a context menu, and VoiceOver gets it as a custom action.
    func swipeToDelete(_ label: String = "Delete", perform: @escaping () -> Void) -> some View {
        modifier(SwipeToDelete(label: label, perform: perform))
    }
}

private struct SwipeToDelete: ViewModifier {
    var label: String
    var perform: () -> Void

    @State private var offset: CGFloat = 0
    private let reveal: CGFloat = 88
    private let fullSwipe: CGFloat = 220

    func body(content: Content) -> some View {
        content
            // The whole row takes the swipe, including the gaps between its labels.
            .contentShape(Rectangle())
            .overlay {
                // While open, a tap on the row closes it instead of triggering the row's own action.
                if offset != 0 {
                    Color.clear.contentShape(Rectangle()).onTapGesture { close() }
                }
            }
            .offset(x: offset)
            .background(alignment: .trailing) {
                if offset < 0 {
                    Button(action: delete) {
                        Text(label).font(.sans(14, .semibold)).foregroundStyle(.white)
                            .lineLimit(1).fixedSize()
                            .frame(width: -offset).frame(maxHeight: .infinity)
                            .background(Color.red)
                    }
                    .buttonStyle(.plain)
                }
            }
            .clipped()
            #if os(iOS)
            .gesture(HorizontalPan(onChange: { t in
                offset = t < 0 ? t : 0
            }, onEnd: { t, v in
                withAnimation(.snappy) {
                    if t < -fullSwipe { delete() }
                    else if t < -reveal / 2 || v < -600 { offset = -reveal }
                    else { offset = 0 }
                }
            }))
            #endif
            .contextMenu { Button(label, role: .destructive, action: perform) }
            .accessibilityAction(named: Text(label), perform)
    }

    private func close() { withAnimation(.snappy) { offset = 0 } }

    private func delete() {
        offset = 0
        perform()
    }
}

#if os(iOS)
/// A pan that only begins when the finger moves sideways, so vertical scrolling is never captured.
private struct HorizontalPan: UIGestureRecognizerRepresentable {
    var onChange: (CGFloat) -> Void
    var onEnd: (_ translation: CGFloat, _ velocity: CGFloat) -> Void

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let pan = UIPanGestureRecognizer()
        pan.delegate = context.coordinator
        return pan
    }

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator() }

    func handleUIGestureRecognizerAction(_ pan: UIPanGestureRecognizer, context: Context) {
        let t = pan.translation(in: pan.view).x
        switch pan.state {
        case .changed: onChange(t)
        case .ended, .cancelled, .failed: onEnd(t, pan.velocity(in: pan.view).x)
        default: break
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
            guard let pan = g as? UIPanGestureRecognizer else { return false }
            let v = pan.velocity(in: pan.view)
            return abs(v.x) > abs(v.y) * 1.2
        }

        /// The enclosing scroll view waits for this pan to fail; it fails at once on vertical movement,
        /// so scrolling isn't delayed, but a sideways swipe reaches the row instead of the scroll view.
        func gestureRecognizer(_ g: UIGestureRecognizer, shouldBeRequiredToFailBy other: UIGestureRecognizer) -> Bool {
            other.view is UIScrollView
        }
    }
}
#endif
