import SwiftUI

public struct JishuReviewView: View {

    var presenter: JishuReviewPresenter

    private let options: [(symbol: String, label: LocalizedStringKey)] = [
        ("1.circle.fill", "jishu.review.rating.terrible"),
        ("2.circle.fill", "jishu.review.rating.bad"),
        ("3.circle.fill", "jishu.review.rating.okay"),
        ("4.circle.fill", "jishu.review.rating.good"),
        ("5.circle.fill", "jishu.review.rating.great"),
    ]

    public init(presenter: JishuReviewPresenter) {
        self.presenter = presenter
    }

    public var body: some View {
        VStack(spacing: 20) {
            Text(presenter.promptTitle)
                .font(.title2.bold())

            Text(presenter.promptQuestion)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 0) {
                ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                    Button {
                        presenter.submit(rating: index + 1)
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: option.symbol)
                                #if os(watchOS)
                                .font(.title3)
                                #else
                                .font(.system(size: 38))
                                #endif
                            #if !os(watchOS)
                            Text(option.label, bundle: .module)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            #endif
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .tint(.primary)
                }
            }
            .padding(.top, 4)
        }
        #if os(watchOS)
        .padding(12)
        #else
        .padding(24)
        .presentationDetents([.height(220)])
        .presentationDragIndicator(.visible)
        #endif
    }
}
