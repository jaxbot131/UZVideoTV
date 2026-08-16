import XCTest

final class UZVideoTVUITests: XCTestCase {
    func testRecommendationAggregationAndFilters() {
        let allTab = app.buttons["recommend-tab-all"]
        XCTAssertTrue(allTab.waitForExistence(timeout: 20))
        XCTAssertTrue(app.staticTexts["recommend-status"].exists)

        XCUIRemote.shared.press(.right)
        let tvTab = app.buttons["recommend-tab-tv"]
        XCTAssertTrue(tvTab.hasFocus)
        XCUIRemote.shared.press(.select)

        XCTAssertTrue(app.staticTexts["类型"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["地区"].exists)
        XCTAssertTrue(app.staticTexts["年代"].exists)
        XCTAssertTrue(app.staticTexts["平台"].exists)
        XCTAssertTrue(app.staticTexts["排序"].exists)
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot(), quality: .original)
        attachment.name = "recommendation-filters"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private var app: XCUIApplication!
    private let remote = XCUIRemote.shared

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments.append("-UITesting")
        if name.contains("RecommendationAggregationAndFilters") {
            app.launchArguments.append("-UITestRecommend")
        }
        app.launch()
    }

    func testSourceCategoriesEpisodePlaybackAndBottomNavigation() {
        let sourceButton = app.buttons["sourcePickerButton"]
        XCTAssertTrue(sourceButton.waitForExistence(timeout: 30), "首页没有出现视频源按钮")
        XCTAssertTrue(sourceButton.label.localizedCaseInsensitiveContains("ikun"), "测试没有选择可播放的 ikun 源：\(sourceButton.label)")
        XCTAssertTrue(waitForFocus(sourceButton, timeout: 5), "视频源按钮不能获得遥控器焦点")

        remote.press(.right)
        XCTAssertTrue(waitForFocus(app.buttons["header-history"], timeout: 3), "右上角播放历史不能获得焦点")
        remote.press(.right)
        XCTAssertTrue(waitForFocus(app.buttons["header-favorites"], timeout: 3), "右上角收藏不能获得焦点")
        remote.press(.right)
        XCTAssertTrue(waitForFocus(app.buttons["header-search"], timeout: 3), "右上角搜索不能获得焦点")
        remote.press(.left)
        XCTAssertTrue(waitForFocus(app.buttons["header-favorites"], timeout: 3), "搜索不能返回收藏")
        remote.press(.left)
        XCTAssertTrue(waitForFocus(app.buttons["header-history"], timeout: 3), "收藏不能返回播放历史")
        remote.press(.left)
        XCTAssertTrue(waitForFocus(sourceButton, timeout: 3), "右上角功能栏不能返回视频源")

        remote.press(.select)
        XCTAssertTrue(app.staticTexts["分享码 1111 共 75 个视频源"].waitForExistence(timeout: 5), "没有完整导入 1111 的 75 个视频源")

        let selectedSource = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'source-'")).matching(NSPredicate(format: "hasFocus == true")).firstMatch
        XCTAssertTrue(selectedSource.waitForExistence(timeout: 5), "视频源列表没有默认焦点")
        remote.press(.select)

        XCTAssertTrue(app.buttons["category-1"].waitForExistence(timeout: 30), "没有从源站取得分类")

        let posters = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'poster-'"))
        let firstPoster = posters.firstMatch
        XCTAssertTrue(firstPoster.waitForExistence(timeout: 15), "首页没有可选择的海报")
        var focusedPoster = posters.matching(NSPredicate(format: "hasFocus == true")).firstMatch
        for _ in 0..<4 where !focusedPoster.exists {
            remote.press(.down)
            RunLoop.current.run(until: Date().addingTimeInterval(0.35))
            focusedPoster = posters.matching(NSPredicate(format: "hasFocus == true")).firstMatch
        }
        XCTAssertTrue(focusedPoster.exists, "遥控器焦点不能进入海报网格")
        remote.press(.select)

        XCTAssertTrue(app.staticTexts["选集"].waitForExistence(timeout: 15), "点击海报后没有进入详情")
        let episodes = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'episode-'"))
        let firstEpisode = episodes.firstMatch
        XCTAssertTrue(firstEpisode.waitForExistence(timeout: 10), "详情页没有正片/剧集")
        XCTAssertTrue(waitForFocus(firstEpisode, timeout: 5), "正片/剧集没有获得默认遥控器焦点")
        remote.press(.select)
        let playerScreen = app.otherElements["playerScreen"]
        XCTAssertTrue(playerScreen.waitForExistence(timeout: 10), "选择剧集后没有进入播放器")
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == 'ready'"), object: playerScreen)
        let readyResult = XCTWaiter.wait(for: [ready], timeout: 25)
        XCTAssertEqual(readyResult, .completed, "视频流没有进入可播放状态，播放器状态：\(String(describing: playerScreen.value))")

        remote.press(.select)
        remote.press(.up)
        RunLoop.current.run(until: Date().addingTimeInterval(1))
        let playerAttachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        playerAttachment.name = "native-tvOS-player-controls"
        playerAttachment.lifetime = .keepAlways
        add(playerAttachment)

        remote.press(.menu)
        if !app.staticTexts["选集"].waitForExistence(timeout: 1) {
            remote.press(.menu)
        }
        XCTAssertTrue(app.staticTexts["选集"].waitForExistence(timeout: 5), "播放器 Menu 键没有返回选集")
        remote.press(.menu)
        XCTAssertTrue(sourceButton.waitForExistence(timeout: 5), "详情 Menu 键没有返回首页")

        for _ in 0..<8 { remote.press(.down) }
        for _ in 0..<5 { remote.press(.left) }
        let home = app.buttons["bottom-首页"]
        let focusedButtons = app.buttons.matching(NSPredicate(format: "hasFocus == true")).allElementsBoundByIndex.map { "\($0.identifier):\($0.label)" }.joined(separator: ", ")
        XCTAssertTrue(home.hasFocus, "遥控器焦点不能进入底部菜单；当前焦点：\(focusedButtons)")

        remote.press(.up)
        XCTAssertTrue(waitForFocus(sourceButton, timeout: 5), "从底部菜单向上不能稳定返回内容区")
        for _ in 0..<10 where !home.hasFocus {
            remote.press(.down)
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        XCTAssertTrue(home.hasFocus, "从内容区不能再次进入底部菜单")

        for _ in 0..<4 { remote.press(.right) }
        let settings = app.buttons["bottom-设置"]
        XCTAssertTrue(settings.hasFocus, "遥控器焦点不能切换到底部设置")
        remote.press(.select)
        XCTAssertTrue(app.staticTexts["数据管理"].waitForExistence(timeout: 5), "底部菜单无法打开设置")

        remote.press(.up)
        let settingsData = app.buttons["settings-data"]
        XCTAssertTrue(waitForFocus(settingsData, timeout: 5), "设置页向上不能进入可见内容")
        remote.press(.select)
        XCTAssertTrue(app.buttons["data-subscription"].waitForExistence(timeout: 5), "数据管理二级菜单没有显示高对比订阅入口")
        XCTAssertTrue(app.buttons["data-sources"].exists, "数据管理二级菜单没有显示高对比视频源入口")
        let settingsAttachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        settingsAttachment.name = "high-contrast-data-management"
        settingsAttachment.lifetime = .keepAlways
        add(settingsAttachment)
        remote.press(.menu)
        XCTAssertTrue(settingsData.waitForExistence(timeout: 5), "数据管理不能返回设置")
        XCTAssertTrue(waitForFocus(settingsData, timeout: 5), "返回设置后数据管理没有恢复焦点")
        for _ in 0..<10 where !settings.hasFocus {
            remote.press(.down)
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        XCTAssertTrue(settings.hasFocus, "设置内容不能返回底部菜单")

        for _ in 0..<4 { remote.press(.left) }
        XCTAssertTrue(home.hasFocus, "底部菜单不能返回首页按钮")
        remote.press(.select)
        XCTAssertTrue(app.buttons["sourcePickerButton"].waitForExistence(timeout: 5), "底部菜单无法切换回首页")
    }

    func testSearchScreenAppearance() {
        let sourceButton = app.buttons["sourcePickerButton"]
        XCTAssertTrue(sourceButton.waitForExistence(timeout: 30))
        XCTAssertTrue(waitForFocus(sourceButton, timeout: 5))
        remote.press(.right)
        remote.press(.right)
        remote.press(.right)
        XCTAssertTrue(waitForFocus(app.buttons["header-search"], timeout: 5))
        remote.press(.select)
        XCTAssertTrue(app.staticTexts["搜索"].waitForExistence(timeout: 5))
        let searchField = app.textFields["search-field"]
        XCTAssertTrue(waitForFocus(searchField, timeout: 5), "搜索框没有高对比默认焦点")
        remote.press(.down)
        let focusedResult = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'search-result-' AND hasFocus == true")).firstMatch
        XCTAssertTrue(focusedResult.waitForExistence(timeout: 5), "搜索结果不能获得遥控器焦点")
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "search-screen"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func waitForFocus(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if element.hasFocus { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return element.hasFocus
    }
}
