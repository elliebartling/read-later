import SwiftData
import XCTest
@testable import ReadLater

/// YouTube Wave 2 one-time subscription import: the two pure normalization seams
/// (Takeout CSV + logged-in `feed/channels` DOM anchors) and the model's
/// dedupe/selection logic. The live harvest (`YouTubeSubscriptionHarvester`)
/// can't be exercised without a real Google login, so its DOM→channel mapping is
/// isolated behind `YouTubeSubscriptionImport.channels(fromAnchors:)` and
/// fixture-tested here against a captured anchor shape.
final class YouTubeImportTests: XCTestCase {

    // MARK: - Takeout subscriptions.csv

    /// The documented Takeout shape: header + `Channel Id,Channel Url,Channel Title`.
    func testCSVParsesDocumentedFormat() {
        let csv = """
        Channel Id,Channel Url,Channel Title
        UCYO_jab_esuFRV4b17AJtAw,http://www.youtube.com/channel/UCYO_jab_esuFRV4b17AJtAw,3Blue1Brown
        UCsXVk37bltHxD1rDPwtNM8Q,http://www.youtube.com/channel/UCsXVk37bltHxD1rDPwtNM8Q,Kurzgesagt
        """
        let channels = YouTubeSubscriptionImport.channels(fromCSV: csv)
        XCTAssertEqual(channels.count, 2)
        XCTAssertEqual(channels[0].channelID, "UCYO_jab_esuFRV4b17AJtAw")
        XCTAssertEqual(channels[0].title, "3Blue1Brown")
        XCTAssertEqual(channels[0].directFeedURL?.absoluteString,
                       "https://www.youtube.com/feeds/videos.xml?channel_id=UCYO_jab_esuFRV4b17AJtAw")
        XCTAssertEqual(channels[1].title, "Kurzgesagt")
    }

    /// Titles with commas are quoted; a leading BOM and CRLF line endings appear
    /// in real Takeout exports.
    func testCSVHandlesQuotedFieldsBOMandCRLF() {
        let csv = "\u{FEFF}Channel Id,Channel Url,Channel Title\r\n"
            + "UCYO_jab_esuFRV4b17AJtAw,http://www.youtube.com/channel/UCYO_jab_esuFRV4b17AJtAw,\"Lastname, Firstname\"\r\n"
            + "UCsXVk37bltHxD1rDPwtNM8Q,http://www.youtube.com/channel/UCsXVk37bltHxD1rDPwtNM8Q,\"He said \"\"hi\"\"\"\r\n"
        let channels = YouTubeSubscriptionImport.channels(fromCSV: csv)
        XCTAssertEqual(channels.count, 2)
        XCTAssertEqual(channels[0].title, "Lastname, Firstname")
        XCTAssertEqual(channels[1].title, "He said \"hi\"")
    }

    /// A first row that is already data (no header) still parses under the
    /// documented column order.
    func testCSVWithoutHeader() {
        let csv = "UCYO_jab_esuFRV4b17AJtAw,http://www.youtube.com/channel/UCYO_jab_esuFRV4b17AJtAw,3Blue1Brown"
        let channels = YouTubeSubscriptionImport.channels(fromCSV: csv)
        XCTAssertEqual(channels.count, 1)
        XCTAssertEqual(channels.first?.channelID, "UCYO_jab_esuFRV4b17AJtAw")
    }

    /// Reordered header columns must be honored, not assumed.
    func testCSVReorderedHeaderColumns() {
        let csv = """
        Channel Title,Channel Id,Channel Url
        3Blue1Brown,UCYO_jab_esuFRV4b17AJtAw,http://www.youtube.com/channel/UCYO_jab_esuFRV4b17AJtAw
        """
        let channels = YouTubeSubscriptionImport.channels(fromCSV: csv)
        XCTAssertEqual(channels.count, 1)
        XCTAssertEqual(channels.first?.channelID, "UCYO_jab_esuFRV4b17AJtAw")
        XCTAssertEqual(channels.first?.title, "3Blue1Brown")
    }

    func testCSVSkipsInvalidAndDeduplicates() {
        let csv = """
        Channel Id,Channel Url,Channel Title
        not-a-channel-id,http://x,Junk
        UCYO_jab_esuFRV4b17AJtAw,http://www.youtube.com/channel/UCYO_jab_esuFRV4b17AJtAw,3Blue1Brown

        UCYO_jab_esuFRV4b17AJtAw,http://www.youtube.com/channel/UCYO_jab_esuFRV4b17AJtAw,3Blue1Brown (dupe)
        """
        let channels = YouTubeSubscriptionImport.channels(fromCSV: csv)
        XCTAssertEqual(channels.count, 1)
        XCTAssertEqual(channels.first?.title, "3Blue1Brown")
    }

    func testEmptyCSVYieldsNothing() {
        XCTAssertTrue(YouTubeSubscriptionImport.channels(fromCSV: "").isEmpty)
        XCTAssertTrue(YouTubeSubscriptionImport.channels(fromCSV: "Channel Id,Channel Url,Channel Title\n").isEmpty)
    }

    // MARK: - feed/channels DOM anchors

    func testAnchorsClassifyChannelIDsHandlesAndVanity() {
        let anchors: [[String: String]] = [
            ["href": "/channel/UCYO_jab_esuFRV4b17AJtAw", "name": "3Blue1Brown"],
            ["href": "/@veritasium", "name": "Veritasium"],
            ["href": "/c/mkbhd", "name": "MKBHD"],
            ["href": "/user/vsauce1", "name": "Vsauce"],
            ["href": "https://www.youtube.com/channel/UCsXVk37bltHxD1rDPwtNM8Q", "name": "Kurzgesagt"],
        ]
        let channels = YouTubeSubscriptionImport.channels(fromAnchors: anchors)
        XCTAssertEqual(channels.count, 5)
        XCTAssertEqual(channels[0].channelID, "UCYO_jab_esuFRV4b17AJtAw")
        XCTAssertEqual(channels[0].directFeedURL?.absoluteString,
                       "https://www.youtube.com/feeds/videos.xml?channel_id=UCYO_jab_esuFRV4b17AJtAw")
        // Handle-only channels carry no id (resolved at subscribe time).
        XCTAssertNil(channels[1].channelID)
        XCTAssertEqual(channels[1].reference, "https://www.youtube.com/@veritasium")
        XCTAssertNil(channels[1].directFeedURL)
        XCTAssertEqual(channels[2].reference, "https://www.youtube.com/c/mkbhd")
        XCTAssertEqual(channels[3].reference, "https://www.youtube.com/user/vsauce1")
        XCTAssertEqual(channels[4].channelID, "UCsXVk37bltHxD1rDPwtNM8Q")
    }

    /// A channel is linked twice on the page (avatar with no text + the name
    /// link) — it must collapse to one row, and non-channel links are dropped.
    func testAnchorsDeduplicateAndDropNonChannelLinks() {
        let anchors: [[String: String]] = [
            ["href": "/channel/UCYO_jab_esuFRV4b17AJtAw", "name": ""],
            ["href": "/channel/UCYO_jab_esuFRV4b17AJtAw", "name": "3Blue1Brown"],
            ["href": "/watch?v=aircAruvnKk", "name": "some video"],
            ["href": "/feed/subscriptions", "name": "nav"],
            ["href": "/@veritasium", "name": "Veritasium"],
            ["href": "/@veritasium/videos", "name": "Veritasium videos tab"],
        ]
        let channels = YouTubeSubscriptionImport.channels(fromAnchors: anchors)
        // 3Blue1Brown once (id key) + Veritasium once (handle reference key).
        XCTAssertEqual(channels.count, 2)
        // First occurrence wins, but the empty-name row falls back to reference,
        // so the titled duplicate does not overwrite — id-keyed dedupe keeps the
        // first (empty-name) row's title fallback.
        XCTAssertEqual(channels.first?.channelID, "UCYO_jab_esuFRV4b17AJtAw")
    }

    func testEmptyAnchorsYieldNothing() {
        XCTAssertTrue(YouTubeSubscriptionImport.channels(fromAnchors: []).isEmpty)
        XCTAssertTrue(YouTubeSubscriptionImport.channels(fromAnchors: [["name": "no href"]]).isEmpty)
    }

    // MARK: - Model dedupe + selection

    @MainActor
    func testPresentSplitsAlreadySubscribed() {
        let model = YouTubeImportModel()
        let channels = [
            ImportableChannel(title: "3Blue1Brown", reference: "x", channelID: "UCYO_jab_esuFRV4b17AJtAw"),
            ImportableChannel(title: "Kurzgesagt", reference: "y", channelID: "UCsXVk37bltHxD1rDPwtNM8Q"),
            ImportableChannel(title: "Handle Only", reference: "https://www.youtube.com/@handle", channelID: nil),
        ]
        model.present(channels: channels, existingChannelIDs: ["UCYO_jab_esuFRV4b17AJtAw"])
        XCTAssertEqual(model.phase, .picking)
        XCTAssertEqual(model.alreadySubscribedCount, 1)
        XCTAssertEqual(model.newChannels.count, 2)
        XCTAssertEqual(model.newChannels.map(\.title), ["Kurzgesagt", "Handle Only"])
        XCTAssertTrue(model.selection.isEmpty, "nothing pre-checked")
    }

    @MainActor
    func testSelectAllAndToggle() {
        let model = YouTubeImportModel()
        let channels = [
            ImportableChannel(title: "A", reference: "a", channelID: "UCaaaaaaaaaaaaaaaaaaaaaa"),
            ImportableChannel(title: "B", reference: "b", channelID: "UCbbbbbbbbbbbbbbbbbbbbbb"),
        ]
        model.present(channels: channels, existingChannelIDs: [])
        XCTAssertFalse(model.canSubscribe)
        model.selectAll()
        XCTAssertTrue(model.allSelected)
        XCTAssertTrue(model.canSubscribe)
        model.toggle(channels[0])
        XCTAssertFalse(model.isSelected(channels[0]))
        XCTAssertFalse(model.allSelected)
        model.deselectAll()
        XCTAssertTrue(model.selection.isEmpty)
    }

    @MainActor
    func testExistingChannelIDsExtractedFromFeedURLs() {
        let yt = Feed(feedURL: URL(string: "https://www.youtube.com/feeds/videos.xml?channel_id=UCYO_jab_esuFRV4b17AJtAw")!)
        let plain = Feed(feedURL: URL(string: "https://daringfireball.net/feeds/main")!)
        let ids = YouTubeImportModel.existingChannelIDs(in: [yt, plain])
        XCTAssertEqual(ids, ["UCYO_jab_esuFRV4b17AJtAw"])
    }
}
