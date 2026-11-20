public struct SheepAtlas {
    public let column: Int
    public let row: Int
    public init(provider: String, status: String) {
        row = ["claude", "claude-code"].contains(provider) ? 1 : 0
        column = ["sleeping", "idle", "waiting"].contains(status) ? 1 : 0
    }
}
