//
//  ReportListingSheet.swift
//  ebiketrader
//

import SwiftUI

struct ReportListingSheet: View {
    let listing: Listing

    @EnvironmentObject private var auth: AuthStore

    var body: some View {
        ReportSheet(
            title: "Report listing",
            footnote: "We review every report. You can also block this seller so their listings stop appearing for you.",
            identity: [
                "kind": "listing",
                "listingId": listing.id,
                "listingTitle": listing.title,
                "listingSellerId": listing.sellerId,
                "reporterId": auth.uid ?? "",
            ]
        )
    }
}
