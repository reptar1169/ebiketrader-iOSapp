//
//  SelectableText.swift
//  ebiketrader
//

import SwiftUI
import UIKit

extension UIFont {
    /// A weighted variant of a Dynamic Type text style. Going through the
    /// descriptor (and size 0) keeps the style's scaled point size, so this
    /// still responds to the reader's text-size setting.
    func withWeight(_ weight: UIFont.Weight) -> UIFont {
        let descriptor = fontDescriptor.addingAttributes([
            .traits: [UIFontDescriptor.TraitKey.weight: weight],
        ])
        return UIFont(descriptor: descriptor, size: 0)
    }
}

/// Read-only text you can actually select a *part* of — drag handles, Copy,
/// Look Up, Translate, the lot.
///
/// SwiftUI's own .textSelection(.enabled) doesn't do this on iOS: it only
/// attaches a Copy/Share callout for the whole Text view. Partial selection
/// needs a real UITextView, so this wraps one in non-editable, non-scrolling
/// mode and lets SwiftUI size it.
struct SelectableText: UIViewRepresentable {
    let text: String
    var font: UIFont = .preferredFont(forTextStyle: .subheadline)
    var color: UIColor = .label
    var alignment: NSTextAlignment = .natural
    /// false fills the offered width (paragraphs, message bubbles); true
    /// shrinks to the text's own width so it can sit right-aligned in a row.
    var hugsContent = false
    /// Appends a destructive item to the native selection menu. The message
    /// bubbles use this for Delete: a UITextView takes over the long press,
    /// so a SwiftUI .contextMenu on top of it would never fire.
    var destructiveAction: (title: String, perform: () -> Void)?

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.isEditable = false
        view.isSelectable = true
        view.isScrollEnabled = false
        view.backgroundColor = .clear
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.adjustsFontForContentSizeCategory = true
        view.delegate = context.coordinator
        // Without this the text view collapses instead of growing to fit.
        view.setContentCompressionResistancePriority(.required, for: .vertical)
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        context.coordinator.destructiveAction = destructiveAction
        if view.text != text { view.text = text }
        view.font = font
        view.textColor = color
        view.textAlignment = alignment
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        let offered = proposal.width ?? UIView.layoutFittingExpandedSize.width
        let ideal = uiView.sizeThatFits(CGSize(width: offered, height: .greatestFiniteMagnitude))
        let width = hugsContent ? min(ideal.width, offered) : offered
        // Re-measure at the width actually being used, or a paragraph that
        // wraps differently ends up with the wrong height.
        let height = uiView.sizeThatFits(
            CGSize(width: width, height: .greatestFiniteMagnitude)
        ).height
        return CGSize(width: width, height: height)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(destructiveAction: destructiveAction)
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var destructiveAction: (title: String, perform: () -> Void)?

        init(destructiveAction: (title: String, perform: () -> Void)?) {
            self.destructiveAction = destructiveAction
        }

        func textView(
            _ textView: UITextView,
            editMenuForTextIn range: NSRange,
            suggestedActions: [UIMenuElement]
        ) -> UIMenu? {
            guard let destructiveAction else { return nil }
            let action = UIAction(
                title: destructiveAction.title,
                image: UIImage(systemName: "trash"),
                attributes: .destructive
            ) { _ in destructiveAction.perform() }
            return UIMenu(children: suggestedActions + [action])
        }
    }
}
