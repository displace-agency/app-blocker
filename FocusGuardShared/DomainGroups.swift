import Foundation

public struct DomainGroup: Identifiable {
    public let id: String
    public let name: String
    public let icon: String // SF Symbol name
    public let domains: [String]

    public init(id: String, name: String, icon: String, domains: [String]) {
        self.id = id
        self.name = name
        self.icon = icon
        self.domains = domains
    }
}

public enum DomainGroups {
    public static let all: [DomainGroup] = [
        socialMedia,
        video,
        news,
        streaming,
        gaming,
        shopping,
    ]

    public static let socialMedia = DomainGroup(
        id: "social",
        name: "Social Media",
        icon: "bubble.left.and.bubble.right.fill",
        domains: [
            "x.com",
            "twitter.com",
            "facebook.com",
            "instagram.com",
            "tiktok.com",
            "snapchat.com",
            "reddit.com",
            "threads.net",
            "pinterest.com",
            "tumblr.com",
            "mastodon.social",
            "bsky.app",
            "linkedin.com",
            "quora.com",
            "discord.com",
        ]
    )

    public static let video = DomainGroup(
        id: "video",
        name: "Video",
        icon: "play.rectangle.fill",
        domains: [
            "youtube.com",
            "m.youtube.com",
            "youtu.be",
            "youtube-nocookie.com",
            "ytimg.com",
            "i.ytimg.com",
            "yt3.ggpht.com",
            "twitch.tv",
            "dailymotion.com",
            "vimeo.com",
            "rumble.com",
            "odysee.com",
        ]
    )

    public static let news = DomainGroup(
        id: "news",
        name: "News",
        icon: "newspaper.fill",
        domains: [
            "cnn.com",
            "bbc.com",
            "bbc.co.uk",
            "foxnews.com",
            "nytimes.com",
            "washingtonpost.com",
            "theguardian.com",
            "reuters.com",
            "apnews.com",
            "nbcnews.com",
            "abcnews.go.com",
            "cbsnews.com",
            "usatoday.com",
            "huffpost.com",
            "dailymail.co.uk",
            "nypost.com",
            "politico.com",
            "thehill.com",
            "axios.com",
            "vox.com",
            "bloomberg.com",
            "cnbc.com",
            "forbes.com",
            "businessinsider.com",
            "techcrunch.com",
            "theverge.com",
            "wired.com",
            "arstechnica.com",
            "engadget.com",
            "mashable.com",
            "slate.com",
            "thedailybeast.com",
            "independent.co.uk",
            "telegraph.co.uk",
            "bild.de",
            "spiegel.de",
            "elpais.com",
            "elmundo.es",
            "lemonde.fr",
            "corriere.it",
            "repubblica.it",
            "news.yahoo.com",
            "news.google.com",
            "msn.com",
            "newsweek.com",
            "time.com",
            "theatlantic.com",
            "newyorker.com",
            "npr.org",
            "aljazeera.com",
            "rt.com",
        ]
    )

    public static let streaming = DomainGroup(
        id: "streaming",
        name: "Streaming",
        icon: "tv.fill",
        domains: [
            "netflix.com",
            "primevideo.com",
            "disneyplus.com",
            "hulu.com",
            "max.com",
            "hbomax.com",
            "peacocktv.com",
            "paramountplus.com",
            "tv.apple.com",
            "crunchyroll.com",
            "pluto.tv",
            "tubitv.com",
            "plex.tv",
            "curiositystream.com",
            "mubi.com",
            "dazn.com",
            "espn.com",
            "fubo.tv",
            "sling.com",
        ]
    )

    public static let gaming = DomainGroup(
        id: "gaming",
        name: "Gaming",
        icon: "gamecontroller.fill",
        domains: [
            "store.steampowered.com",
            "steampowered.com",
            "steamcommunity.com",
            "epicgames.com",
            "ea.com",
            "blizzard.com",
            "battle.net",
            "riotgames.com",
            "leagueoflegends.com",
            "gog.com",
            "itch.io",
            "roblox.com",
            "minecraft.net",
            "xbox.com",
            "playstation.com",
            "nintendolife.com",
            "ign.com",
            "gamespot.com",
            "kotaku.com",
            "polygon.com",
        ]
    )

    public static let shopping = DomainGroup(
        id: "shopping",
        name: "Shopping",
        icon: "cart.fill",
        domains: [
            "amazon.com",
            "amazon.co.uk",
            "amazon.de",
            "amazon.es",
            "ebay.com",
            "aliexpress.com",
            "wish.com",
            "etsy.com",
            "walmart.com",
            "target.com",
            "bestbuy.com",
            "shein.com",
            "temu.com",
            "asos.com",
            "zara.com",
            "hm.com",
            "uniqlo.com",
            "nike.com",
            "adidas.com",
            "zalando.com",
        ]
    )
}
