import SwiftUI
import AppKit

// MARK: - Native SVG Vector Path Parser

public struct SVGPathParser {
    public static func parse(_ d: String) -> CGPath {
        let path = CGMutablePath()
        
        var formatted = d
        for char in "MmLlHhVvCcSsQqAaZz" {
            formatted = formatted.replacingOccurrences(of: String(char), with: " \(char) ")
        }
        // Separate minus signs and back-to-back decimals
        formatted = formatted.replacingOccurrences(of: "(?<=[0-9.])(?=-)", with: " ", options: .regularExpression)
        formatted = formatted.replacingOccurrences(of: "(?<=\\.[0-9]{1,10})(?=\\.)", with: " ", options: .regularExpression)
        
        let tokens = formatted.split(whereSeparator: { $0.isWhitespace || $0 == "," }).map(String.init)
        var i = 0
        var currentPoint = CGPoint.zero
        var currentCommand: Character = " "
        
        func nextDouble() -> Double? {
            guard i < tokens.count else { return nil }
            if let val = Double(tokens[i]) {
                i += 1
                return val
            }
            return nil
        }
        
        while i < tokens.count {
            let token = tokens[i]
            if token.count == 1, let first = token.first, "MmLlHhVvCcSsQqAaZz".contains(first) {
                currentCommand = first
                i += 1
            }
            
            switch currentCommand {
            case "M":
                if let x = nextDouble(), let y = nextDouble() {
                    currentPoint = CGPoint(x: x, y: y)
                    path.move(to: currentPoint)
                    currentCommand = "L"
                } else { i += 1 }
            case "m":
                if let dx = nextDouble(), let dy = nextDouble() {
                    currentPoint = CGPoint(x: currentPoint.x + dx, y: currentPoint.y + dy)
                    path.move(to: currentPoint)
                    currentCommand = "l"
                } else { i += 1 }
            case "L":
                if let x = nextDouble(), let y = nextDouble() {
                    currentPoint = CGPoint(x: x, y: y)
                    path.addLine(to: currentPoint)
                } else { i += 1 }
            case "l":
                if let dx = nextDouble(), let dy = nextDouble() {
                    currentPoint = CGPoint(x: currentPoint.x + dx, y: currentPoint.y + dy)
                    path.addLine(to: currentPoint)
                } else { i += 1 }
            case "H":
                if let x = nextDouble() {
                    currentPoint = CGPoint(x: x, y: currentPoint.y)
                    path.addLine(to: currentPoint)
                } else { i += 1 }
            case "h":
                if let dx = nextDouble() {
                    currentPoint = CGPoint(x: currentPoint.x + dx, y: currentPoint.y)
                    path.addLine(to: currentPoint)
                } else { i += 1 }
            case "V":
                if let y = nextDouble() {
                    currentPoint = CGPoint(x: currentPoint.x, y: y)
                    path.addLine(to: currentPoint)
                } else { i += 1 }
            case "v":
                if let dy = nextDouble() {
                    currentPoint = CGPoint(x: currentPoint.x, y: currentPoint.y + dy)
                    path.addLine(to: currentPoint)
                } else { i += 1 }
            case "C":
                if let x1 = nextDouble(), let y1 = nextDouble(),
                   let x2 = nextDouble(), let y2 = nextDouble(),
                   let x = nextDouble(), let y = nextDouble() {
                    let cp1 = CGPoint(x: x1, y: y1)
                    let cp2 = CGPoint(x: x2, y: y2)
                    currentPoint = CGPoint(x: x, y: y)
                    path.addCurve(to: currentPoint, control1: cp1, control2: cp2)
                } else { i += 1 }
            case "c":
                if let dx1 = nextDouble(), let dy1 = nextDouble(),
                   let dx2 = nextDouble(), let dy2 = nextDouble(),
                   let dx = nextDouble(), let dy = nextDouble() {
                    let cp1 = CGPoint(x: currentPoint.x + dx1, y: currentPoint.y + dy1)
                    let cp2 = CGPoint(x: currentPoint.x + dx2, y: currentPoint.y + dy2)
                    currentPoint = CGPoint(x: currentPoint.x + dx, y: currentPoint.y + dy)
                    path.addCurve(to: currentPoint, control1: cp1, control2: cp2)
                } else { i += 1 }
            case "Q":
                if let cx = nextDouble(), let cy = nextDouble(),
                   let x = nextDouble(), let y = nextDouble() {
                    currentPoint = CGPoint(x: x, y: y)
                    path.addQuadCurve(to: currentPoint, control: CGPoint(x: cx, y: cy))
                } else { i += 1 }
            case "q":
                if let dcx = nextDouble(), let dcy = nextDouble(),
                   let dx = nextDouble(), let dy = nextDouble() {
                    let cp = CGPoint(x: currentPoint.x + dcx, y: currentPoint.y + dcy)
                    currentPoint = CGPoint(x: currentPoint.x + dx, y: currentPoint.y + dy)
                    path.addQuadCurve(to: currentPoint, control: cp)
                } else { i += 1 }
            case "S", "s":
                if let _ = nextDouble(), let _ = nextDouble(),
                   let x = nextDouble(), let y = nextDouble() {
                    currentPoint = currentCommand.isUppercase ? CGPoint(x: x, y: y) : CGPoint(x: currentPoint.x + x, y: currentPoint.y + y)
                    path.addLine(to: currentPoint)
                } else { i += 1 }
            case "Z", "z":
                path.closeSubpath()
            default:
                i += 1
            }
        }
        
        return path
    }
}

public struct SVGVectorShape: Shape {
    public let basePath: Path
    public let originalBounds: CGRect
    
    public init(pathString: String, viewBox: CGRect? = nil) {
        let cgPath = SVGPathParser.parse(pathString)
        self.basePath = Path(cgPath)
        self.originalBounds = viewBox ?? cgPath.boundingBox
    }
    
    public func path(in rect: CGRect) -> Path {
        guard originalBounds.width > 0, originalBounds.height > 0 else { return Path() }
        var transform = CGAffineTransform.identity
        let scaleX = rect.width / originalBounds.width
        let scaleY = rect.height / originalBounds.height
        let scale = min(scaleX, scaleY)
        
        let offsetX = (rect.width - originalBounds.width * scale) / 2 - originalBounds.minX * scale
        let offsetY = (rect.height - originalBounds.height * scale) / 2 - originalBounds.minY * scale
        
        transform = transform.translatedBy(x: offsetX, y: offsetY).scaledBy(x: scale, y: scale)
        return basePath.applying(transform)
    }
}

// MARK: - Git Provider Logos

public struct GitHubLogoView: View {
    public var size: CGFloat = 18
    private static let pathString = "M127.505 0C57.095 0 0 57.085 0 127.505c0 56.336 36.534 104.13 87.196 120.99 6.372 1.18 8.712-2.766 8.712-6.134 0-3.04-.119-13.085-.173-23.739-35.473 7.713-42.958-15.044-42.958-15.044-5.8-14.738-14.157-18.656-14.157-18.656-11.568-7.914.872-7.752.872-7.752 12.804.9 19.546 13.14 19.546 13.14 11.372 19.493 29.828 13.857 37.104 10.6 1.144-8.242 4.449-13.866 8.095-17.05-28.32-3.225-58.092-14.158-58.092-63.014 0-13.92 4.981-25.295 13.138-34.224-1.324-3.212-5.688-16.18 1.235-33.743 0 0 10.707-3.427 35.073 13.07 10.17-2.826 21.078-4.242 31.914-4.29 10.836.048 21.752 1.464 31.942 4.29 24.337-16.497 35.029-13.07 35.029-13.07 6.94 17.563 2.574 30.531 1.25 33.743 8.175 8.929 13.122 20.303 13.122 34.224 0 48.972-29.828 59.756-58.22 62.912 4.573 3.957 8.648 11.717 8.648 23.612 0 17.06-.148 30.791-.148 34.991 0 3.393 2.295 7.369 8.759 6.117 50.634-16.879 87.122-64.656 87.122-120.973C255.009 57.085 197.922 0 127.505 0"
    private static let viewBox = CGRect(x: 0, y: 0, width: 256, height: 249)
    
    public init(size: CGFloat = 18) {
        self.size = size
    }
    
    public var body: some View {
        SVGVectorShape(pathString: Self.pathString, viewBox: Self.viewBox)
            .fill(Color.primary)
            .frame(width: size, height: size)
    }
}

public struct GitLabLogoView: View {
    public var size: CGFloat = 18
    private static let viewBox = CGRect(x: 0, y: 0, width: 960.2, height: 923.9)
    
    private static let pathBase = "m958.9 442.4c1.1 26.1-2 52.1-9.2 77.2-7.1 25.1-18.3 48.8-33.1 70.3a240.43 240.43 0 0 1 -53.6 56.2l-.5.4-199.9 149.8-98.3 74.5-59.9 45.2c-3.5 2.7-7.4 4.7-11.5 6.1s-8.5 2.1-12.9 2.1c-4.3 0-8.7-.7-12.8-2.1s-8-3.4-11.5-6.1l-59.9-45.2-98.3-74.5-198.7-148.9-1.2-.8-.4-.4c-20.9-15.7-39-34.7-53.8-56.2s-26-45.3-33.2-70.4c-7.2-25.1-10.3-51.2-9.2-77.3 1.2-26.1 6.5-51.8 15.8-76.2l1.3-3.5 130.7-340.5q1-2.5 2.4-4.8 1.3-2.3 3.1-4.3 1.7-2.1 3.7-3.9 2-1.7 4.2-3.2c3.1-1.9 6.3-3.3 9.8-4.1 3.4-.9 7-1.3 10.5-1.1 3.6.2 7.1.9 10.4 2.2 3.3 1.2 6.5 3 9.3 5.2q2 1.7 3.9 3.6 1.8 2 3.2 4.3 1.5 2.2 2.6 4.7 1.1 2.4 1.8 5l88.1 269.7h356.6l88.1-269.7q.7-2.6 1.9-5 1.1-2.4 2.6-4.7 1.4-2.2 3.2-4.2 1.8-2 3.9-3.7c2.8-2.2 5.9-3.9 9.2-5.2 3.4-1.2 6.9-1.9 10.4-2.1 3.6-.2 7.1.1 10.6 1 3.4.9 6.7 2.3 9.7 4.2q2.3 1.4 4.3 3.2 2 1.7 3.7 3.8 1.7 2.1 3.1 4.4 1.3 2.3 2.3 4.8l130.5 340.6 1.3 3.5c9.3 24.3 14.6 50 15.7 76.1z"
    private static let pathRight = "m959 442.5c1.1 26-2 52.1-9.2 77.2s-18.4 48.9-33.2 70.4-32.9 40.5-53.7 56.2l-.5.4-199.9 149.8s-84.9-64.1-182.5-138l286.5-216.8c12.9-9.7 26.4-18.6 40.3-26.8 13.9-8.3 28.3-15.7 43-22.3 14.8-6.6 29.9-12.5 45.2-17.4 15.4-5 31-9.1 46.9-12.4l1.3 3.5c9.3 24.4 14.6 50.1 15.8 76.2z"
    private static let pathChin = "m480 658.5c97.6 73.7 182.6 138 182.6 138l-98.3 74.5-59.9 45.2c-3.5 2.7-7.4 4.7-11.5 6.1s-8.5 2.1-12.9 2.1c-4.3 0-8.7-.7-12.8-2.1s-8-3.4-11.5-6.1l-59.9-45.2-98.3-74.5s84.9-64.3 182.5-138z"
    private static let pathLeft = "m480 658.3c-97.7 73.9-182.5 138-182.5 138l-198.7-148.9-1.2-.8-.4-.4c-20.9-15.7-39-34.7-53.8-56.2s-26-45.3-33.2-70.4c-7.2-25.1-10.3-51.2-9.2-77.3 1.2-26.1 6.5-51.8 15.8-76.2l1.3-3.5c15.9 3.3 31.5 7.4 46.9 12.4 15.3 5 30.4 10.8 45.2 17.5 14.7 6.6 29.1 14.1 43 22.3s27.3 17.2 40.3 26.9z"
    
    public var isMonochrome: Bool = false
    
    public init(size: CGFloat = 18, isMonochrome: Bool = false) {
        self.size = size
        self.isMonochrome = isMonochrome
    }
    
    public var body: some View {
        ZStack {
            if isMonochrome {
                SVGVectorShape(pathString: Self.pathBase, viewBox: Self.viewBox)
                    .fill(Color.primary.opacity(0.8))
            } else {
                SVGVectorShape(pathString: Self.pathBase, viewBox: Self.viewBox)
                    .fill(Color(red: 226/255, green: 67/255, blue: 41/255))
                
                SVGVectorShape(pathString: Self.pathRight, viewBox: Self.viewBox)
                    .fill(Color(red: 252/255, green: 109/255, blue: 38/255))
                
                SVGVectorShape(pathString: Self.pathLeft, viewBox: Self.viewBox)
                    .fill(Color(red: 252/255, green: 109/255, blue: 38/255))
                
                SVGVectorShape(pathString: Self.pathChin, viewBox: Self.viewBox)
                    .fill(Color(red: 252/255, green: 163/255, blue: 38/255))
            }
        }
        .frame(width: size, height: size)
    }
}

public struct BitbucketLogoView: View {
    public var size: CGFloat = 18
    private static let viewBox = CGRect(x: 0, y: 0, width: 24, height: 24)
    
    private static let pathBack = "M2.6 3c-.6 0-1 .4-1 .9l1.6 15.3c.1.7.7 1.2 1.4 1.2h14.8c.7 0 1.3-.5 1.4-1.2L22.4 3.9c.1-.5-.3-.9-1-.9H2.6zm11.3 13.2H9.3l-1.9-7.5h8l-1.5 7.5z"
    private static let pathFront = "M22.4 3.9L20.8 19.2c-.1.7-.7 1.2-1.4 1.2H12.6l3.3-12.8h5.5c.6 0 1 .4 1 .9z"
    
    public var isMonochrome: Bool = false
    
    public init(size: CGFloat = 18, isMonochrome: Bool = false) {
        self.size = size
        self.isMonochrome = isMonochrome
    }
    
    public var body: some View {
        ZStack {
            if isMonochrome {
                SVGVectorShape(pathString: Self.pathBack, viewBox: Self.viewBox)
                    .fill(Color.primary.opacity(0.8))
            } else {
                SVGVectorShape(pathString: Self.pathBack, viewBox: Self.viewBox)
                    .fill(Color(red: 38/255, green: 132/255, blue: 255/255))
                
                SVGVectorShape(pathString: Self.pathFront, viewBox: Self.viewBox)
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color(red: 0/255, green: 82/255, blue: 204/255),
                                Color(red: 38/255, green: 132/255, blue: 255/255)
                            ]),
                            startPoint: .topTrailing,
                            endPoint: .bottomLeading
                        )
                    )
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Confluence Logo (Atlassian)

public struct ConfluenceLogoView: View {
    public var size: CGFloat = 18
    private static let viewBox = CGRect(x: 0, y: 0, width: 256, height: 246)
    
    private static let pathBottom = "m9.11 187.79c-2.64 4.3-5.63 9.34-7.99 13.33-.52.89-.85 1.88-1 2.9a8.13 8.13 0 0 0 .16 3.07c.24 1.01.68 1.95 1.28 2.79s1.36 1.56 2.23 2.12l53.03 32.69c.91.57 1.94.95 3.01 1.12 1.06.17 2.16.13 3.21-.13s2.04-.72 2.91-1.36 1.6-1.45 2.15-2.38c2.14-3.56 4.85-8.17 7.76-13.09 21.02-34.47 42.32-30.25 80.37-12.16l52.6 24.94a8.13 8.13 0 0 0 6.35.29c1.02-.38 1.96-.96 2.75-1.71.8-.75 1.43-1.65 1.87-2.65l25.25-56.93c.43-.96.67-1.99.7-3.04.04-1.04-.13-2.09-.49-3.07s-.9-1.89-1.6-2.67-1.54-1.41-2.49-1.88c-11.09-5.22-33.16-15.49-52.94-25.17-71.95-34.71-132.66-32.42-179.12 42.99z"
    private static let pathTop = "m246.88 58.38c2.67-4.3 5.66-9.33 7.99-13.32.53-.91.88-1.92 1.03-2.97.15-1.04.09-2.11-.17-3.13a8.155 8.155 0 0 0 -1.36-2.83 8.09 8.09 0 0 0 -2.33-2.11l-52.95-32.69c-.92-.57-1.94-.95-3.01-1.12s-2.16-.12-3.21.13c-1.05.26-2.04.72-2.91 1.36s-1.6 1.45-2.16 2.38c-2.09 3.56-4.85 8.17-7.76 13.09-21.1 34.63-42.2 30.41-80.29 12.32l-52.55-24.95c-.98-.47-2.04-.75-3.12-.81-1.08-.07-2.17.09-3.19.45s-1.96.92-2.76 1.65c-.81.73-1.45 1.61-1.91 2.59l-25.25 57.09a8.191 8.191 0 0 0 -.23 6.13c.36.99.91 1.9 1.61 2.68s1.55 1.42 2.5 1.88c11.13 5.23 33.2 15.49 52.94 25.18 71.76 34.7 132.66 32.42 179.09-43z"
    
    public init(size: CGFloat = 18) {
        self.size = size
    }
    
    public var body: some View {
        ZStack {
            SVGVectorShape(pathString: Self.pathBottom, viewBox: Self.viewBox)
                .fill(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color(red: 0/255, green: 82/255, blue: 204/255),
                            Color(red: 35/255, green: 128/255, blue: 251/255),
                            Color(red: 38/255, green: 132/255, blue: 255/255)
                        ]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            SVGVectorShape(pathString: Self.pathTop, viewBox: Self.viewBox)
                .fill(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color(red: 0/255, green: 82/255, blue: 204/255),
                            Color(red: 35/255, green: 128/255, blue: 251/255),
                            Color(red: 38/255, green: 132/255, blue: 255/255)
                        ]),
                        startPoint: .bottomTrailing,
                        endPoint: .topLeading
                    )
                )
        }
        .frame(width: size, height: size)
    }
}

// MARK: - OpenRouter Logo

public struct OpenRouterLogoView: View {
    public var size: CGFloat = 18
    private static let svgString = """
    <svg fill="#000000" fill-rule="evenodd" viewBox="0 0 24 24" width="64" height="64" xmlns="http://www.w3.org/2000/svg">
    <path d="M18.654 3.87a5.087 5.087 0 110 10.174L23.7 19.09c.64.641.187 1.737-.72 1.737H8.48a8.479 8.479 0 010-16.958h10.175zM8.479 7.26a5.087 5.087 0 100 10.176 5.087 5.087 0 000-10.175z"/>
    </svg>
    """
    
    public init(size: CGFloat = 18) {
        self.size = size
    }
    
    public var body: some View {
        NativeSVGView(svg: Self.svgString, size: size, isTemplate: true)
    }
}

// MARK: - Linear Logo

public struct LinearLogoView: View {
    public var size: CGFloat = 18
    private static let svgString = """
    <svg xmlns="http://www.w3.org/2000/svg" fill="#000000" width="64" height="64" viewBox="0 0 100 100">
    <path fill="#000000" d="M1.22541 61.5228c-.2225-.9485.90748-1.5459 1.59638-.857L39.3342 97.1782c.6889.6889.0915 1.8189-.857 1.5964C20.0515 94.4522 5.54779 79.9485 1.22541 61.5228ZM.00189135 46.8891c-.01764375.2833.08887215.5599.28957165.7606L52.3503 99.7085c.2007.2007.4773.3075.7606.2896 2.3692-.1476 4.6938-.46 6.9624-.9259.7645-.157 1.0301-1.0963.4782-1.6481L2.57595 39.4485c-.55186-.5519-1.49117-.2863-1.648174.4782-.465915 2.2686-.77832 4.5932-.92588465 6.9624ZM4.21093 29.7054c-.16649.3738-.08169.8106.20765 1.1l64.77602 64.776c.2894.2894.7262.3742 1.1.2077 1.7861-.7956 3.5171-1.6927 5.1855-2.684.5521-.328.6373-1.0867.1832-1.5407L8.43566 24.3367c-.45409-.4541-1.21271-.3689-1.54074.1832-.99132 1.6684-1.88843 3.3994-2.68399 5.1855ZM12.6587 18.074c-.3701-.3701-.393-.9637-.0443-1.3541C21.7795 6.45931 35.1114 0 49.9519 0 77.5927 0 100 22.4073 100 50.0481c0 14.8405-6.4593 28.1724-16.7199 37.3375-.3903.3487-.984.3258-1.3542-.0443L12.6587 18.074Z"/>
    </svg>
    """
    
    public init(size: CGFloat = 18) {
        self.size = size
    }
    
    public var body: some View {
        NativeSVGView(svg: Self.svgString, size: size, isTemplate: true)
    }
}

// MARK: - Native SVG Vector View

public struct NativeSVGView: View {
    public let svg: String
    public var size: CGFloat = 18
    public var isTemplate: Bool = true
    
    public init(svg: String, size: CGFloat = 18, isTemplate: Bool = true) {
        self.svg = svg
        self.size = size
        self.isTemplate = isTemplate
    }
    
    /// Parsed SVGs are cached: NSImage(data:) parses the SVG on the main thread, and this view's body
    /// is re-evaluated on every EngineClient update (dozens of logos in Models Library / API Keys).
    @MainActor private static var cache: [String: NSImage] = [:]
    
    @MainActor private var nsImage: NSImage? {
        let key = (isTemplate ? "T|" : "O|") + svg
        if let cached = Self.cache[key] { return cached }
        guard let data = svg.data(using: .utf8), let img = NSImage(data: data) else { return nil }
        img.isTemplate = isTemplate
        Self.cache[key] = img
        return img
    }
    
    public var body: some View {
        Group {
            if let img = nsImage {
                Image(nsImage: img)
                    .renderingMode(isTemplate ? .template : .original)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                EmptyView()
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - OpenAI Logo

public struct OpenAILogoView: View {
    public var size: CGFloat = 18
    private static let svgString = """
    <svg fill="#000000" fill-rule="evenodd" viewBox="0 0 24 24" width="64" height="64" xmlns="http://www.w3.org/2000/svg">
    <path d="M9.205 8.658v-2.26c0-.19.072-.333.238-.428l4.543-2.616c.619-.357 1.356-.523 2.117-.523 2.854 0 4.662 2.212 4.662 4.566 0 .167 0 .357-.024.547l-4.71-2.759a.797.797 0 00-.856 0l-5.97 3.473zm10.609 8.8V12.06c0-.333-.143-.57-.429-.737l-5.97-3.473 1.95-1.118a.433.433 0 01.476 0l4.543 2.617c1.309.76 2.189 2.378 2.189 3.948 0 1.808-1.07 3.473-2.76 4.163zM7.802 12.703l-1.95-1.142c-.167-.095-.239-.238-.239-.428V5.899c0-2.545 1.95-4.472 4.591-4.472 1 0 1.927.333 2.712.928L8.23 5.067c-.285.166-.428.404-.428.737v6.898zM12 15.128l-2.795-1.57v-3.33L12 8.658l2.795 1.57v3.33L12 15.128zm1.796 7.23c-1 0-1.927-.332-2.712-.927l4.686-2.712c.285-.166.428-.404.428-.737v-6.898l1.974 1.142c.167.095.238.238.238.428v5.233c0 2.545-1.974 4.472-4.614 4.472zm-5.637-5.303l-4.544-2.617c-1.308-.761-2.188-2.378-2.188-3.948A4.482 4.482 0 014.21 6.327v5.423c0 .333.143.571.428.738l5.947 3.449-1.95 1.118a.432.432 0 01-.476 0zm-.262 3.9c-2.688 0-4.662-2.021-4.662-4.519 0-.19.024-.38.047-.57l4.686 2.71c.286.167.571.167.856 0l5.97-3.448v2.26c0 .19-.07.333-.237.428l-4.543 2.616c-.619.357-1.356.523-2.117.523zm5.899 2.83a5.947 5.947 0 005.827-4.756C22.287 18.339 24 15.84 24 13.296c0-1.665-.713-3.282-1.998-4.448.119-.5.19-.999.19-1.498 0-3.401-2.759-5.947-5.946-5.947-.642 0-1.26.095-1.88.31A5.962 5.962 0 0010.205 0a5.947 5.947 0 00-5.827 4.757C1.713 5.447 0 7.945 0 10.49c0 1.666.713 3.283 1.998 4.448-.119.5-.19 1-.19 1.499 0 3.401 2.759 5.946 5.946 5.946.642 0 1.26-.095 1.88-.309a5.96 5.96 0 004.162 1.713z"/>
    </svg>
    """
    
    public init(size: CGFloat = 18) {
        self.size = size
    }
    
    public var body: some View {
        NativeSVGView(svg: Self.svgString, size: size, isTemplate: true)
    }
}

public struct GitProviderBrandLogo: View {
    public let provider: String
    public var size: CGFloat = 18
    public var isMonochrome: Bool = false
    
    public init(provider: String, size: CGFloat = 18, isMonochrome: Bool = false) {
        self.provider = provider
        self.size = size
        self.isMonochrome = isMonochrome
    }
    
    public var body: some View {
        switch provider.lowercased() {
        case "gitlab":
            GitLabLogoView(size: size, isMonochrome: isMonochrome)
        case "bitbucket":
            BitbucketLogoView(size: size, isMonochrome: isMonochrome)
        default:
            GitHubLogoView(size: size)
        }
    }
}

// MARK: - Dicty Brand Logo

public struct DictyBrandLogoView: View {
    public var size: CGFloat = 16
    private static let svgString = """
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="64" height="64">
        <rect width="1024" height="1024" rx="230" ry="230" fill="#506658" />
        <g fill="none" stroke="#ffffff" stroke-width="70" stroke-linecap="round" stroke-linejoin="round">
            <path d="M 360 360 L 210 512 L 360 664" />
            <path d="M 664 360 L 814 512 L 664 664" />
            <path d="M 426 410 L 426 614" />
            <path d="M 512 330 L 512 694" />
            <path d="M 598 410 L 598 614" />
        </g>
    </svg>
    """
    
    public init(size: CGFloat = 16) {
        self.size = size
    }
    
    public var body: some View {
        NativeSVGView(svg: Self.svgString, size: size, isTemplate: false)
    }
}

// MARK: - Local Server Logo (Original Vector)

public struct LocalServerLogoView: View {
    public var size: CGFloat = 16
    private static let svgString = """
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="64" height="64" fill="none" stroke="#000000" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
        <rect x="2" y="3" width="20" height="7" rx="2"/>
        <rect x="2" y="14" width="20" height="7" rx="2"/>
        <line x1="6" y1="6.5" x2="6.01" y2="6.5"/>
        <line x1="6" y1="17.5" x2="6.01" y2="17.5"/>
        <path d="M14 6.5h4M14 17.5h4"/>
    </svg>
    """
    
    public init(size: CGFloat = 16) {
        self.size = size
    }
    
    public var body: some View {
        NativeSVGView(svg: Self.svgString, size: size, isTemplate: true)
    }
}

// MARK: - Git Provider Segmented Picker

public struct GitProviderSegmentedPicker: View {
    @Binding public var selection: String
    public let providers: [(id: String, name: String)] = [
        ("github", "GitHub"),
        ("gitlab", "GitLab"),
        ("bitbucket", "Bitbucket")
    ]
    
    @Environment(\.colorScheme) var colorScheme
    @Namespace private var animationNamespace
    
    public init(selection: Binding<String>) {
        self._selection = selection
    }
    
    public var body: some View {
        HStack(spacing: 6) {
            ForEach(providers, id: \.id) { item in
                let isSelected = selection == item.id
                
                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                        selection = item.id
                    }
                }) {
                    HStack(spacing: 8) {
                        GitProviderBrandLogo(provider: item.id, size: 16, isMonochrome: true)
                        
                        Text(item.name)
                            .font(.system(size: 13, weight: isSelected ? .semibold : .medium, design: .rounded))
                            .foregroundColor(isSelected ? .primary : .dictySecondary)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .frame(maxWidth: .infinity)
                    .background(
                        ZStack {
                            if isSelected {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color.appAccent.opacity(0.15))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .stroke(Color.appAccent.opacity(0.3), lineWidth: 1)
                                    )
                                    .matchedGeometryEffect(id: "activeProviderPill", in: animationNamespace)
                            }
                        }
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(
                    colorScheme == .dark 
                        ? Color.black.opacity(0.25) 
                        : Color.black.opacity(0.06)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }
}

// MARK: - LLM Provider Segmented Picker

public struct LLMProviderSegmentedPicker: View {
    @Binding public var selection: String
    public let providers: [(id: String, name: String)] = [
        ("dicty_cloud", "Dicty Cloud"),
        ("openrouter", "OpenRouter"),
        ("local", "Local Server")
    ]
    
    @Environment(\.colorScheme) var colorScheme
    @Namespace private var animationNamespace
    
    public init(selection: Binding<String>) {
        self._selection = selection
    }
    
    public var body: some View {
        HStack(spacing: 6) {
            ForEach(providers, id: \.id) { item in
                let isSelected = selection == item.id
                
                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                        selection = item.id
                    }
                }) {
                    HStack(spacing: 7) {
                        providerIcon(for: item.id)
                        
                        Text(item.name)
                            .font(.system(size: 12.5, weight: isSelected ? .semibold : .medium, design: .rounded))
                            .foregroundColor(isSelected ? .primary : .dictySecondary)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .frame(maxWidth: .infinity)
                    .background(
                        ZStack {
                            if isSelected {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(
                                        colorScheme == .dark 
                                            ? Color.white.opacity(0.14) 
                                            : Color.white.opacity(0.9)
                                    )
                                    .matchedGeometryEffect(id: "activeLLMProviderPill", in: animationNamespace)
                                    .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.3 : 0.08), radius: 3, y: 1.5)
                            }
                        }
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(
                    colorScheme == .dark 
                        ? Color.black.opacity(0.25) 
                        : Color.black.opacity(0.06)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }
    
    @ViewBuilder
    private func providerIcon(for id: String) -> some View {
        switch id {
        case "dicty_cloud":
            DictyBrandLogoView(size: 15)
        case "openrouter":
            OpenRouterLogoView(size: 14)
        case "local":
            LocalServerLogoView(size: 15)
        default:
            EmptyView()
        }
    }
}
    
// MARK: - Local Files Logo (Document / Vault Vector)

public struct LocalFilesLogoView: View {
    public var size: CGFloat = 16
    private static let svgString = """
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="64" height="64" fill="none" stroke="#000000" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
        <path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"/>
        <polyline points="14 2 14 8 20 8"/>
        <line x1="16" y1="13" x2="8" y2="13"/>
        <line x1="16" y1="17" x2="8" y2="17"/>
        <line x1="10" y1="9" x2="8" y2="9"/>
    </svg>
    """
    
    public init(size: CGFloat = 16) {
        self.size = size
    }
    
    public var body: some View {
        NativeSVGView(svg: Self.svgString, size: size, isTemplate: true)
    }
}

// MARK: - Knowledge Base Segmented Picker

public struct KnowledgeBaseSegmentedPicker: View {
    @Binding public var selection: String
    public let systems: [(id: String, name: String)] = [
        ("confluence", "Confluence"),
        ("linear", "Linear"),
        ("notion", "Notion"),
        ("obsidian", "Local Files")
    ]
    
    @Environment(\.colorScheme) var colorScheme
    @Namespace private var animationNamespace
    
    public init(selection: Binding<String>) {
        self._selection = selection
    }
    
    public var body: some View {
        HStack(spacing: 6) {
            ForEach(systems, id: \.id) { item in
                let isSelected = selection == item.id
                
                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                        selection = item.id
                    }
                }) {
                    HStack(spacing: 7) {
                        systemIcon(for: item.id)
                        
                        Text(item.name)
                            .font(.system(size: 12.5, weight: isSelected ? .semibold : .medium, design: .rounded))
                            .foregroundColor(isSelected ? .primary : .dictySecondary)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .frame(maxWidth: .infinity)
                    .background(
                        ZStack {
                            if isSelected {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(
                                        colorScheme == .dark 
                                            ? Color.white.opacity(0.14) 
                                            : Color.white.opacity(0.9)
                                    )
                                    .matchedGeometryEffect(id: "activeKBSegmentPill", in: animationNamespace)
                                    .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.3 : 0.08), radius: 3, y: 1.5)
                            }
                        }
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(
                    colorScheme == .dark 
                        ? Color.black.opacity(0.25) 
                        : Color.black.opacity(0.06)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }
    
    @ViewBuilder
    private func systemIcon(for id: String) -> some View {
        switch id {
        case "confluence":
            ConfluenceLogoView(size: 15)
        case "linear":
            LinearLogoView(size: 15)
        case "notion":
            NotionLogoView(size: 15)
        case "obsidian":
            LocalFilesLogoView(size: 15)
        default:
            EmptyView()
        }
    }
}

// MARK: - Notion Logo
public struct NotionLogoView: View {
    public var size: CGFloat = 18
    private static let svgString = """
    <svg fill="#000000" fill-rule="evenodd" viewBox="0 0 24 24" width="64" height="64" xmlns="http://www.w3.org/2000/svg">
    <path clip-rule="evenodd" d="M15.257.055l-13.31.98C.874 1.128.5 1.83.5 2.667v14.559c0 .654.233 1.213.794 1.96l3.129 4.06c.513.653.98.794 1.962.745l15.457-.932c1.307-.093 1.681-.7 1.681-1.727V4.954c0-.53-.21-.684-.829-1.135l-.106-.078L18.34.755c-1.027-.746-1.45-.84-3.083-.7zm-8.521 4.63c-1.263.086-1.549.105-2.266-.477L2.647 2.76c-.186-.187-.092-.42.375-.466l12.796-.933c1.074-.094 1.634.28 2.054.606l2.195 1.587c.093.047.326.326.047.326l-13.216.794-.162.01zM5.263 21.193V7.287c0-.606.187-.886.748-.933l15.176-.886c.515-.047.748.28.748.886v13.81c0 .609-.093 1.122-.934 1.168l-14.523.84c-.842.047-1.215-.232-1.215-.98zm14.338-13.16c.093.422 0 .842-.422.89l-.699.139v10.264c-.608.327-1.168.513-1.635.513-.747 0-.934-.232-1.495-.932l-4.576-7.185v6.952l1.448.327s0 .84-1.169.84l-3.221.186c-.094-.187 0-.654.327-.747l.84-.232V9.853L7.832 9.76c-.093-.42.14-1.026.794-1.073l3.456-.232 4.763 7.279v-6.44l-1.214-.14c-.094-.513.28-.887.747-.933l3.223-.187z"/>
    </svg>
    """
    
    public init(size: CGFloat = 18) {
        self.size = size
    }
    
    public var body: some View {
        NativeSVGView(svg: Self.svgString, size: size, isTemplate: true)
    }
}

// MARK: - Auto-Generated Provider Icons


public struct QwenLogoView: View {
    public var size: CGFloat = 16
    private static let svgString = """
    <svg height="1em" style="flex:none;line-height:1" viewBox="0 0 24 24" width="1em" xmlns="http://www.w3.org/2000/svg"><title>Qwen</title><path d="M12.604 1.34c.393.69.784 1.382 1.174 2.075a.18.18 0 00.157.091h5.552c.174 0 .322.11.446.327l1.454 2.57c.19.337.24.478.024.837-.26.43-.513.864-.76 1.3l-.367.658c-.106.196-.223.28-.04.512l2.652 4.637c.172.301.111.494-.043.77-.437.785-.882 1.564-1.335 2.34-.159.272-.352.375-.68.37-.777-.016-1.552-.01-2.327.016a.099.099 0 00-.081.05 575.097 575.097 0 01-2.705 4.74c-.169.293-.38.363-.725.364-.997.003-2.002.004-3.017.002a.537.537 0 01-.465-.271l-1.335-2.323a.09.09 0 00-.083-.049H4.982c-.285.03-.553-.001-.805-.092l-1.603-2.77a.543.543 0 01-.002-.54l1.207-2.12a.198.198 0 000-.197 550.951 550.951 0 01-1.875-3.272l-.79-1.395c-.16-.31-.173-.496.095-.965.465-.813.927-1.625 1.387-2.436.132-.234.304-.334.584-.335a338.3 338.3 0 012.589-.001.124.124 0 00.107-.063l2.806-4.895a.488.488 0 01.422-.246c.524-.001 1.053 0 1.583-.006L11.704 1c.341-.003.724.032.9.34zm-3.432.403a.06.06 0 00-.052.03L6.254 6.788a.157.157 0 01-.135.078H3.253c-.056 0-.07.025-.041.074l5.81 10.156c.025.042.013.062-.034.063l-2.795.015a.218.218 0 00-.2.116l-1.32 2.31c-.044.078-.021.118.068.118l5.716.008c.046 0 .08.02.104.061l1.403 2.454c.046.081.092.082.139 0l5.006-8.76.783-1.382a.055.055 0 01.096 0l1.424 2.53a.122.122 0 00.107.062l2.763-.02a.04.04 0 00.035-.02.041.041 0 000-.04l-2.9-5.086a.108.108 0 010-.113l.293-.507 1.12-1.977c.024-.041.012-.062-.035-.062H9.2c-.059 0-.073-.026-.043-.077l1.434-2.505a.107.107 0 000-.114L9.225 1.774a.06.06 0 00-.053-.031zm6.29 8.02c.046 0 .058.02.034.06l-.832 1.465-2.613 4.585a.056.056 0 01-.05.029.058.058 0 01-.05-.029L8.498 9.841c-.02-.034-.01-.052.028-.054l.216-.012 6.722-.012z" fill="url(#lobe-icons-qwen-_R_0_)" fill-rule="nonzero"></path><defs><linearGradient id="lobe-icons-qwen-_R_0_" x1="0%" x2="100%" y1="0%" y2="0%"><stop offset="0%" stop-color="#6336E7" stop-opacity=".84"></stop><stop offset="100%" stop-color="#6F69F7" stop-opacity=".84"></stop></linearGradient></defs></svg>
    """
    
    public init(size: CGFloat = 16) {
        self.size = size
    }
    
    public var body: some View {
        NativeSVGView(svg: Self.svgString, size: size, isTemplate: true)
    }
}

public struct DeepSeekLogoView: View {
    public var size: CGFloat = 16
    private static let svgString = """
    <svg height="1em" style="flex:none;line-height:1" viewBox="0 0 24 24" width="1em" xmlns="http://www.w3.org/2000/svg"><title>DeepSeek</title><path d="M23.748 4.482c-.254-.124-.364.113-.512.234-.051.039-.094.09-.137.136-.372.397-.806.657-1.373.626-.829-.046-1.537.214-2.163.848-.133-.782-.575-1.248-1.247-1.548-.352-.156-.708-.311-.955-.65-.172-.241-.219-.51-.305-.774-.055-.16-.11-.323-.293-.35-.2-.031-.278.136-.356.276-.313.572-.434 1.202-.422 1.84.027 1.436.633 2.58 1.838 3.393.137.093.172.187.129.323-.082.28-.18.552-.266.833-.055.179-.137.217-.329.14a5.526 5.526 0 01-1.736-1.18c-.857-.828-1.631-1.742-2.597-2.458a11.365 11.365 0 00-.689-.471c-.985-.957.13-1.743.388-1.836.27-.098.093-.432-.779-.428-.872.004-1.67.295-2.687.684a3.055 3.055 0 01-.465.137 9.597 9.597 0 00-2.883-.102c-1.885.21-3.39 1.102-4.497 2.623C.082 8.606-.231 10.684.152 12.85c.403 2.284 1.569 4.175 3.36 5.653 1.858 1.533 3.997 2.284 6.438 2.14 1.482-.085 3.133-.284 4.994-1.86.47.234.962.327 1.78.397.63.059 1.236-.03 1.705-.128.735-.156.684-.837.419-.961-2.155-1.004-1.682-.595-2.113-.926 1.096-1.296 2.746-2.642 3.392-7.003.05-.347.007-.565 0-.845-.004-.17.035-.237.23-.256a4.173 4.173 0 001.545-.475c1.396-.763 1.96-2.015 2.093-3.517.02-.23-.004-.467-.247-.588zM11.581 18c-2.089-1.642-3.102-2.183-3.52-2.16-.392.024-.321.471-.235.763.09.288.207.486.371.739.114.167.192.416-.113.603-.673.416-1.842-.14-1.897-.167-1.361-.802-2.5-1.86-3.301-3.307-.774-1.393-1.224-2.887-1.298-4.482-.02-.386.093-.522.477-.592a4.696 4.696 0 011.529-.039c2.132.312 3.946 1.265 5.468 2.774.868.86 1.525 1.887 2.202 2.891.72 1.066 1.494 2.082 2.48 2.914.348.292.625.514.891.677-.802.09-2.14.11-3.054-.614zm1-6.44a.306.306 0 01.415-.287.302.302 0 01.2.288.306.306 0 01-.31.307.303.303 0 01-.304-.308zm3.11 1.596c-.2.081-.399.151-.59.16a1.245 1.245 0 01-.798-.254c-.274-.23-.47-.358-.552-.758a1.73 1.73 0 01.016-.588c.07-.327-.008-.537-.239-.727-.187-.156-.426-.199-.688-.199a.559.559 0 01-.254-.078c-.11-.054-.2-.19-.114-.358.028-.054.16-.186.192-.21.356-.202.767-.136 1.146.016.352.144.618.408 1.001.782.391.451.462.576.685.914.176.265.336.537.445.848.067.195-.019.354-.25.452z" fill="#4D6BFE"></path></svg>
    """
    
    public init(size: CGFloat = 16) {
        self.size = size
    }
    
    public var body: some View {
        NativeSVGView(svg: Self.svgString, size: size, isTemplate: true)
    }
}

public struct ElevenLabsLogoView: View {
    public var size: CGFloat = 16
    private static let svgString = """
    <svg fill="currentColor" fill-rule="evenodd" height="1em" style="flex:none;line-height:1" viewBox="0 0 24 24" width="1em" xmlns="http://www.w3.org/2000/svg"><title>ElevenLabs</title><path d="M5 0h5v24H5V0zM14 0h5v24h-5V0z"></path></svg>
    """
    
    public init(size: CGFloat = 16) {
        self.size = size
    }
    
    public var body: some View {
        NativeSVGView(svg: Self.svgString, size: size, isTemplate: true)
    }
}

public struct GrokLogoView: View {
    public var size: CGFloat = 16
    private static let svgString = """
    <svg fill="currentColor" fill-rule="evenodd" height="1em" style="flex:none;line-height:1" viewBox="0 0 24 24" width="1em" xmlns="http://www.w3.org/2000/svg"><title>Grok</title><path d="M9.27 15.29l7.978-5.897c.391-.29.95-.177 1.137.272.98 2.369.542 5.215-1.41 7.169-1.951 1.954-4.667 2.382-7.149 1.406l-2.711 1.257c3.889 2.661 8.611 2.003 11.562-.953 2.341-2.344 3.066-5.539 2.388-8.42l.006.007c-.983-4.232.242-5.924 2.75-9.383.06-.082.12-.164.179-.248l-3.301 3.305v-.01L9.267 15.292M7.623 16.723c-2.792-2.67-2.31-6.801.071-9.184 1.761-1.763 4.647-2.483 7.166-1.425l2.705-1.25a7.808 7.808 0 00-1.829-1A8.975 8.975 0 005.984 5.83c-2.533 2.536-3.33 6.436-1.962 9.764 1.022 2.487-.653 4.246-2.34 6.022-.599.63-1.199 1.259-1.682 1.925l7.62-6.815"></path></svg>
    """
    
    public init(size: CGFloat = 16) {
        self.size = size
    }
    
    public var body: some View {
        NativeSVGView(svg: Self.svgString, size: size, isTemplate: true)
    }
}

public struct GroqLogoView: View {
    public var size: CGFloat = 16
    private static let svgString = """
    <svg fill="currentColor" fill-rule="evenodd" height="1em" style="flex:none;line-height:1" viewBox="0 0 24 24" width="1em" xmlns="http://www.w3.org/2000/svg"><title>Groq</title><path d="M12.036 2c-3.853-.035-7 3-7.036 6.781-.035 3.782 3.055 6.872 6.908 6.907h2.42v-2.566h-2.292c-2.407.028-4.38-1.866-4.408-4.23-.029-2.362 1.901-4.298 4.308-4.326h.1c2.407 0 4.358 1.915 4.365 4.278v6.305c0 2.342-1.944 4.25-4.323 4.279a4.375 4.375 0 01-3.033-1.252l-1.851 1.818A7 7 0 0012.029 22h.092c3.803-.056 6.858-3.083 6.879-6.816v-6.5C18.907 4.963 15.817 2 12.036 2z"></path></svg>
    """
    
    public init(size: CGFloat = 16) {
        self.size = size
    }
    
    public var body: some View {
        NativeSVGView(svg: Self.svgString, size: size, isTemplate: true)
    }
}

public struct HuggingFaceLogoView: View {
    public var size: CGFloat = 16
    private static let svgString = """
    <svg fill="currentColor" fill-rule="evenodd" height="1em" style="flex:none;line-height:1" viewBox="0 0 24 24" width="1em" xmlns="http://www.w3.org/2000/svg"><title>HuggingFace</title><path d="M16.781 3.277c2.997 1.704 4.844 4.851 4.844 8.258 0 .995-.155 1.955-.443 2.857a1.332 1.332 0 011.125.4 1.41 1.41 0 01.2 1.723c.204.165.352.385.428.632l.017.062c.06.222.12.69-.2 1.166.244.37.279.836.093 1.236-.255.57-.893 1.018-2.128 1.5l-.202.078-.131.048c-.478.173-.89.295-1.061.345l-.086.024c-.89.243-1.808.375-2.732.394-1.32 0-2.3-.36-2.923-1.067a9.852 9.852 0 01-3.18.018C9.778 21.647 8.802 22 7.494 22a11.249 11.249 0 01-2.541-.343l-.221-.06-.273-.08a16.574 16.574 0 01-1.175-.405c-1.237-.483-1.875-.93-2.13-1.501-.186-.4-.151-.867.093-1.236a1.42 1.42 0 01-.2-1.166c.069-.273.226-.516.447-.694a1.41 1.41 0 01.2-1.722c.233-.248.557-.391.917-.407l.078-.001a9.385 9.385 0 01-.44-2.85c0-3.407 1.847-6.554 4.844-8.258a9.822 9.822 0 019.687 0zM4.188 14.758c.125.687 2.357 2.35 2.14 2.707-.19.315-.796-.239-.948-.386l-.041-.04-.168-.147c-.561-.479-2.304-1.9-2.74-1.432-.43.46.119.859 1.055 1.42l.784.467.136.083c1.045.643 1.12.84.95 1.113-.188.295-3.07-2.1-3.34-1.083-.27 1.011 2.942 1.304 2.744 2.006-.2.7-2.265-1.324-2.685-.537-.425.79 2.913 1.718 2.94 1.725l.16.04.175.042c1.227.284 3.565.65 4.435-.604.673-.973.64-1.709-.248-2.61l-.057-.057c-.945-.928-1.495-2.288-1.495-2.288l-.017-.058-.025-.072c-.082-.22-.284-.639-.63-.584-.46.073-.798 1.21.12 1.933l.05.038c.977.721-.195 1.21-.573.534l-.058-.104-.143-.25c-.463-.799-1.282-2.111-1.739-2.397-.532-.332-.907-.148-.782.541zm14.842-.541c-.533.335-1.563 2.074-1.94 2.751a.613.613 0 01-.687.302.436.436 0 01-.176-.098.303.303 0 01-.049-.06l-.014-.028-.008-.02-.007-.019-.003-.013-.003-.017a.289.289 0 01-.004-.048c0-.12.071-.266.25-.427.026-.024.054-.047.084-.07l.047-.036c.022-.016.043-.032.063-.049.883-.71.573-1.81.131-1.917l-.031-.006-.056-.004a.368.368 0 00-.062.006l-.028.005-.042.014-.039.017-.028.015-.028.019-.036.027-.023.02c-.173.158-.273.428-.31.542l-.016.054s-.53 1.309-1.439 2.234l-.054.054c-.365.358-.596.69-.702 1.018-.143.437-.066.868.21 1.353.055.097.117.195.187.296.882 1.275 3.282.876 4.494.59l.286-.07.25-.074c.276-.084.736-.233 1.2-.42l.188-.077.065-.028.064-.028.124-.056.081-.038c.529-.252.964-.543.994-.827l.001-.036a.299.299 0 00-.037-.139c-.094-.176-.271-.212-.491-.168l-.045.01c-.044.01-.09.024-.136.04l-.097.035-.054.022c-.559.23-1.238.705-1.607.745h.006a.452.452 0 01-.05.003h-.024l-.024-.003-.023-.005c-.068-.016-.116-.06-.14-.142a.22.22 0 01-.005-.1c.062-.345.958-.595 1.713-.91l.066-.028c.528-.224.97-.483.985-.832v-.04a.47.47 0 00-.016-.098c-.048-.18-.175-.251-.36-.251-.785 0-2.55 1.36-2.92 1.36-.025 0-.048-.007-.058-.024a.6.6 0 01-.046-.088c-.1-.238.068-.462 1.06-1.066l.209-.126c.538-.32 1.01-.588 1.341-.831.29-.212.475-.406.503-.6l.003-.028c.008-.113-.038-.227-.147-.344a.266.266 0 00-.07-.054l-.034-.015-.013-.005a.403.403 0 00-.13-.02c-.162 0-.369.07-.595.18-.637.313-1.431.952-1.826 1.285l-.249.215-.033.033c-.08.078-.288.27-.493.386l-.071.037-.041.019a.535.535 0 01-.122.036h.005a.346.346 0 01-.031.003l.01-.001-.013.001c-.079.005-.145-.021-.19-.095a.113.113 0 01-.014-.065c.027-.465 2.034-1.991 2.152-2.642l.009-.048c.1-.65-.271-.817-.791-.493zM11.938 2.984c-4.798 0-8.688 3.829-8.688 8.55 0 .692.083 1.364.24 2.008l.008-.009c.252-.298.612-.46 1.017-.46.355.008.699.117.993.312.22.14.465.384.715.694.261-.372.69-.598 1.15-.605.852 0 1.367.728 1.562 1.383l.047.105.06.127c.192.396.595 1.139 1.143 1.68 1.06 1.04 1.324 2.115.8 3.266a8.865 8.865 0 002.024-.014c-.505-1.12-.26-2.17.74-3.186l.066-.066c.695-.684 1.157-1.69 1.252-1.912.195-.655.708-1.383 1.56-1.383.46.007.889.233 1.15.605.25-.31.495-.553.718-.694a1.87 1.87 0 01.99-.312c.357 0 .682.126.925.36.14-.61.215-1.245.215-1.898 0-4.722-3.89-8.55-8.687-8.55zm1.857 8.926l.439-.212c.553-.264.89-.383.89.152 0 1.093-.771 3.208-3.155 3.262h-.184c-2.325-.052-3.116-2.06-3.156-3.175l-.001-.087c0-1.107 1.452.586 3.25.586.716 0 1.379-.272 1.917-.526zm4.017-3.143c.45 0 .813.358.813.8 0 .441-.364.8-.813.8a.806.806 0 01-.812-.8c0-.442.364-.8.812-.8zm-11.624 0c.448 0 .812.358.812.8 0 .441-.364.8-.812.8a.806.806 0 01-.813-.8c0-.442.364-.8.813-.8zm7.79-.841c.32-.384.846-.54 1.33-.394.483.146.83.564.878 1.06.048.495-.212.97-.659 1.203-.322.168-.447-.477-.767-.585l.002-.003c-.287-.098-.772.362-.925.079a1.215 1.215 0 01.14-1.36zm-4.323 0c.322.384.377.92.14 1.36-.152.283-.64-.177-.925-.079l.003.003c-.108.036-.194.134-.273.24l-.118.165c-.11.15-.22.262-.377.18a1.226 1.226 0 01-.658-1.204c.048-.495.395-.913.878-1.059a1.262 1.262 0 011.33.394z"></path></svg>
    """
    
    public init(size: CGFloat = 16) {
        self.size = size
    }
    
    public var body: some View {
        NativeSVGView(svg: Self.svgString, size: size, isTemplate: true)
    }
}

public struct MetaLogoView: View {
    public var size: CGFloat = 16
    private static let svgString = """
    <svg height="1em" style="flex:none;line-height:1" viewBox="0 0 24 24" width="1em" xmlns="http://www.w3.org/2000/svg"><title>Meta</title><path d="M6.897 4h-.024l-.031 2.615h.022c1.715 0 3.046 1.357 5.94 6.246l.175.297.012.02 1.62-2.438-.012-.019a48.763 48.763 0 00-1.098-1.716 28.01 28.01 0 00-1.175-1.629C10.413 4.932 8.812 4 6.896 4z" fill="url(#lobe-icons-meta-0-_R_0_)"></path><path d="M6.873 4C4.95 4.01 3.247 5.258 2.02 7.17a4.352 4.352 0 00-.01.017l2.254 1.231.011-.017c.718-1.083 1.61-1.774 2.568-1.785h.021L6.896 4h-.023z" fill="url(#lobe-icons-meta-1-_R_0_)"></path><path d="M2.019 7.17l-.011.017C1.2 8.447.598 9.995.274 11.664l-.005.022 2.534.6.004-.022c.27-1.467.786-2.828 1.456-3.845l.011-.017L2.02 7.17z" fill="url(#lobe-icons-meta-2-_R_0_)"></path><path d="M2.807 12.264l-2.533-.6-.005.022c-.177.918-.267 1.851-.269 2.786v.023l2.598.233v-.023a12.591 12.591 0 01.21-2.44z" fill="url(#lobe-icons-meta-3-_R_0_)"></path><path d="M2.677 15.537a5.462 5.462 0 01-.079-.813v-.022L0 14.468v.024a8.89 8.89 0 00.146 1.652l2.535-.585a4.106 4.106 0 01-.004-.022z" fill="url(#lobe-icons-meta-4-_R_0_)"></path><path d="M3.27 16.89c-.284-.31-.484-.756-.589-1.328l-.004-.021-2.535.585.004.021c.192 1.01.568 1.85 1.106 2.487l.014.017 2.018-1.745a2.106 2.106 0 01-.015-.016z" fill="url(#lobe-icons-meta-5-_R_0_)"></path><path d="M10.78 9.654c-1.528 2.35-2.454 3.825-2.454 3.825-2.035 3.2-2.739 3.917-3.871 3.917a1.545 1.545 0 01-1.186-.508l-2.017 1.744.014.017C2.01 19.518 3.058 20 4.356 20c1.963 0 3.374-.928 5.884-5.33l1.766-3.13a41.283 41.283 0 00-1.227-1.886z" fill="#0082FB"></path><path d="M13.502 5.946l-.016.016c-.4.43-.786.908-1.16 1.416.378.483.768 1.024 1.175 1.63.48-.743.928-1.345 1.367-1.807l.016-.016-1.382-1.24z" fill="url(#lobe-icons-meta-6-_R_0_)"></path><path d="M20.918 5.713C19.853 4.633 18.583 4 17.225 4c-1.432 0-2.637.787-3.723 1.944l-.016.016 1.382 1.24.016-.017c.715-.747 1.408-1.12 2.176-1.12.826 0 1.6.39 2.27 1.075l.015.016 1.589-1.425-.016-.016z" fill="#0082FB"></path><path d="M23.998 14.125c-.06-3.467-1.27-6.566-3.064-8.396l-.016-.016-1.588 1.424.015.016c1.35 1.392 2.277 3.98 2.361 6.971v.023h2.292v-.022z" fill="url(#lobe-icons-meta-7-_R_0_)"></path><path d="M23.998 14.15v-.023h-2.292v.022c.004.14.006.282.006.424 0 .815-.121 1.474-.368 1.95l-.011.022 1.708 1.782.013-.02c.62-.96.946-2.293.946-3.91 0-.083 0-.165-.002-.247z" fill="url(#lobe-icons-meta-8-_R_0_)"></path><path d="M21.344 16.52l-.011.02c-.214.402-.519.67-.917.787l.778 2.462a3.493 3.493 0 00.438-.182 3.558 3.558 0 001.366-1.218l.044-.065.012-.02-1.71-1.784z" fill="url(#lobe-icons-meta-9-_R_0_)"></path><path d="M19.92 17.393c-.262 0-.492-.039-.718-.14l-.798 2.522c.449.153.927.222 1.46.222.492 0 .943-.073 1.352-.215l-.78-2.462c-.167.05-.341.075-.517.073z" fill="url(#lobe-icons-meta-10-_R_0_)"></path><path d="M18.323 16.534l-.014-.017-1.836 1.914.016.017c.637.682 1.246 1.105 1.937 1.337l.797-2.52c-.291-.125-.573-.353-.9-.731z" fill="url(#lobe-icons-meta-11-_R_0_)"></path><path d="M18.309 16.515c-.55-.642-1.232-1.712-2.303-3.44l-1.396-2.336-.011-.02-1.62 2.438.012.02.989 1.668c.959 1.61 1.74 2.774 2.493 3.585l.016.016 1.834-1.914a2.353 2.353 0 01-.014-.017z" fill="url(#lobe-icons-meta-12-_R_0_)"></path><defs><linearGradient id="lobe-icons-meta-0-_R_0_" x1="75.897%" x2="26.312%" y1="89.199%" y2="12.194%"><stop offset=".06%" stop-color="#0867DF"></stop><stop offset="45.39%" stop-color="#0668E1"></stop><stop offset="85.91%" stop-color="#0064E0"></stop></linearGradient><linearGradient id="lobe-icons-meta-1-_R_0_" x1="21.67%" x2="97.068%" y1="75.874%" y2="23.985%"><stop offset="13.23%" stop-color="#0064DF"></stop><stop offset="99.88%" stop-color="#0064E0"></stop></linearGradient><linearGradient id="lobe-icons-meta-2-_R_0_" x1="38.263%" x2="60.895%" y1="89.127%" y2="16.131%"><stop offset="1.47%" stop-color="#0072EC"></stop><stop offset="68.81%" stop-color="#0064DF"></stop></linearGradient><linearGradient id="lobe-icons-meta-3-_R_0_" x1="47.032%" x2="52.15%" y1="90.19%" y2="15.745%"><stop offset="7.31%" stop-color="#007CF6"></stop><stop offset="99.43%" stop-color="#0072EC"></stop></linearGradient><linearGradient id="lobe-icons-meta-4-_R_0_" x1="52.155%" x2="47.591%" y1="58.301%" y2="37.004%"><stop offset="7.31%" stop-color="#007FF9"></stop><stop offset="100%" stop-color="#007CF6"></stop></linearGradient><linearGradient id="lobe-icons-meta-5-_R_0_" x1="37.689%" x2="61.961%" y1="12.502%" y2="63.624%"><stop offset="7.31%" stop-color="#007FF9"></stop><stop offset="100%" stop-color="#0082FB"></stop></linearGradient><linearGradient id="lobe-icons-meta-6-_R_0_" x1="34.808%" x2="62.313%" y1="68.859%" y2="23.174%"><stop offset="27.99%" stop-color="#007FF8"></stop><stop offset="91.41%" stop-color="#0082FB"></stop></linearGradient><linearGradient id="lobe-icons-meta-7-_R_0_" x1="43.762%" x2="57.602%" y1="6.235%" y2="98.514%"><stop offset="0%" stop-color="#0082FB"></stop><stop offset="99.95%" stop-color="#0081FA"></stop></linearGradient><linearGradient id="lobe-icons-meta-8-_R_0_" x1="60.055%" x2="39.88%" y1="4.661%" y2="69.077%"><stop offset="6.19%" stop-color="#0081FA"></stop><stop offset="100%" stop-color="#0080F9"></stop></linearGradient><linearGradient id="lobe-icons-meta-9-_R_0_" x1="30.282%" x2="61.081%" y1="59.32%" y2="33.244%"><stop offset="0%" stop-color="#027AF3"></stop><stop offset="100%" stop-color="#0080F9"></stop></linearGradient><linearGradient id="lobe-icons-meta-10-_R_0_" x1="20.433%" x2="82.112%" y1="50.001%" y2="50.001%"><stop offset="0%" stop-color="#0377EF"></stop><stop offset="99.94%" stop-color="#0279F1"></stop></linearGradient><linearGradient id="lobe-icons-meta-11-_R_0_" x1="40.303%" x2="72.394%" y1="35.298%" y2="57.811%"><stop offset=".19%" stop-color="#0471E9"></stop><stop offset="100%" stop-color="#0377EF"></stop></linearGradient><linearGradient id="lobe-icons-meta-12-_R_0_" x1="32.254%" x2="68.003%" y1="19.719%" y2="84.908%"><stop offset="27.65%" stop-color="#0867DF"></stop><stop offset="100%" stop-color="#0471E9"></stop></linearGradient></defs></svg>
    """
    
    public init(size: CGFloat = 16) {
        self.size = size
    }
    
    public var body: some View {
        NativeSVGView(svg: Self.svgString, size: size, isTemplate: true)
    }
}

public struct MiniMaxLogoView: View {
    public var size: CGFloat = 16
    private static let svgString = """
    <svg height="1em" style="flex:none;line-height:1" viewBox="0 0 24 24" width="1em" xmlns="http://www.w3.org/2000/svg"><title>Minimax</title><defs><linearGradient id="lobe-icons-minimax-_R_0_" x1="0%" x2="100.182%" y1="50.057%" y2="50.057%"><stop offset="0%" stop-color="#E2167E"></stop><stop offset="100%" stop-color="#FE603C"></stop></linearGradient></defs><path d="M16.278 2c1.156 0 2.093.927 2.093 2.07v12.501a.74.74 0 00.744.709.74.74 0 00.743-.709V9.099a2.06 2.06 0 012.071-2.049A2.06 2.06 0 0124 9.1v6.561a.649.649 0 01-.652.645.649.649 0 01-.653-.645V9.1a.762.762 0 00-.766-.758.762.762 0 00-.766.758v7.472a2.037 2.037 0 01-2.048 2.026 2.037 2.037 0 01-2.048-2.026v-12.5a.785.785 0 00-.788-.753.785.785 0 00-.789.752l-.001 15.904A2.037 2.037 0 0113.441 22a2.037 2.037 0 01-2.048-2.026V18.04c0-.356.292-.645.652-.645.36 0 .652.289.652.645v1.934c0 .263.142.506.372.638.23.131.514.131.744 0a.734.734 0 00.372-.638V4.07c0-1.143.937-2.07 2.093-2.07zm-5.674 0c1.156 0 2.093.927 2.093 2.07v11.523a.648.648 0 01-.652.645.648.648 0 01-.652-.645V4.07a.785.785 0 00-.789-.78.785.785 0 00-.789.78v14.013a2.06 2.06 0 01-2.07 2.048 2.06 2.06 0 01-2.071-2.048V9.1a.762.762 0 00-.766-.758.762.762 0 00-.766.758v3.8a2.06 2.06 0 01-2.071 2.049A2.06 2.06 0 010 12.9v-1.378c0-.357.292-.646.652-.646.36 0 .653.29.653.646V12.9c0 .418.343.757.766.757s.766-.339.766-.757V9.099a2.06 2.06 0 012.07-2.048 2.06 2.06 0 012.071 2.048v8.984c0 .419.343.758.767.758.423 0 .766-.339.766-.758V4.07c0-1.143.937-2.07 2.093-2.07z" fill="url(#lobe-icons-minimax-_R_0_)" fill-rule="nonzero"></path></svg>
    """
    
    public init(size: CGFloat = 16) {
        self.size = size
    }
    
    public var body: some View {
        NativeSVGView(svg: Self.svgString, size: size, isTemplate: true)
            .scaleEffect(1.15)
    }
}

public struct MoonshotLogoView: View {
    public var size: CGFloat = 16
    private static let svgString = """
    <svg fill="currentColor" fill-rule="evenodd" height="1em" style="flex:none;line-height:1" viewBox="0 0 24 24" width="1em" xmlns="http://www.w3.org/2000/svg"><title>MoonshotAI</title><path d="M1.052 16.916l9.539 2.552a21.007 21.007 0 00.06 2.033l5.956 1.593a11.997 11.997 0 01-5.586.865l-.18-.016-.044-.004-.084-.009-.094-.01a11.605 11.605 0 01-.157-.02l-.107-.014-.11-.016a11.962 11.962 0 01-.32-.051l-.042-.008-.075-.013-.107-.02-.07-.015-.093-.019-.075-.016-.095-.02-.097-.023-.094-.022-.068-.017-.088-.022-.09-.024-.095-.025-.082-.023-.109-.03-.062-.02-.084-.025-.093-.028-.105-.034-.058-.019-.08-.026-.09-.031-.066-.024a6.293 6.293 0 01-.044-.015l-.068-.025-.101-.037-.057-.022-.08-.03-.087-.035-.088-.035-.079-.032-.095-.04-.063-.028-.063-.027a5.655 5.655 0 01-.041-.018l-.066-.03-.103-.047-.052-.024-.096-.046-.062-.03-.084-.04-.086-.044-.093-.047-.052-.027-.103-.055-.057-.03-.058-.032a6.49 6.49 0 01-.046-.026l-.094-.053-.06-.034-.051-.03-.072-.041-.082-.05-.093-.056-.052-.032-.084-.053-.061-.039-.079-.05-.07-.047-.053-.035a7.785 7.785 0 01-.054-.036l-.044-.03-.044-.03a6.066 6.066 0 01-.04-.028l-.057-.04-.076-.054-.069-.05-.074-.054-.056-.042-.076-.057-.076-.059-.086-.067-.045-.035-.064-.052-.074-.06-.089-.073-.046-.039-.046-.039a7.516 7.516 0 01-.043-.037l-.045-.04-.061-.053-.07-.062-.068-.06-.062-.058-.067-.062-.053-.05-.088-.084a13.28 13.28 0 01-.099-.097l-.029-.028-.041-.042-.069-.07-.05-.051-.05-.053a6.457 6.457 0 01-.168-.179l-.08-.088-.062-.07-.071-.08-.042-.049-.053-.062-.058-.068-.046-.056a7.175 7.175 0 01-.027-.033l-.045-.055-.066-.082-.041-.052-.05-.064-.02-.025a11.99 11.99 0 01-1.44-2.402zm-1.02-5.794l11.353 3.037a20.468 20.468 0 00-.469 2.011l10.817 2.894a12.076 12.076 0 01-1.845 2.005L.657 15.923l-.016-.046-.035-.104a11.965 11.965 0 01-.05-.153l-.007-.023a11.896 11.896 0 01-.207-.741l-.03-.126-.018-.08-.021-.097-.018-.081-.018-.09-.017-.084-.018-.094c-.026-.141-.05-.283-.071-.426l-.017-.118-.011-.083-.013-.102a12.01 12.01 0 01-.019-.161l-.005-.047a12.12 12.12 0 01-.034-2.145zm1.593-5.15l11.948 3.196c-.368.605-.705 1.231-1.01 1.875l11.295 3.022c-.142.82-.368 1.612-.668 2.365l-11.55-3.09L.124 10.26l.015-.1.008-.049.01-.067.015-.087.018-.098c.026-.148.056-.295.088-.442l.028-.124.02-.085.024-.097c.022-.09.045-.18.07-.268l.028-.102.023-.083.03-.1.025-.082.03-.096.026-.082.031-.095a11.896 11.896 0 011.01-2.232zm4.442-4.4L17.352 4.59a20.77 20.77 0 00-1.688 1.721l7.823 2.093c.267.852.442 1.744.513 2.665L2.106 5.213l.045-.065.027-.04.04-.055.046-.065.055-.076.054-.072.064-.086.05-.065.057-.073.055-.07.06-.074.055-.069.065-.077.054-.066.066-.077.053-.06.072-.082.053-.06.067-.074.054-.058.073-.078.058-.06.063-.067.168-.17.1-.098.059-.056.076-.071a12.084 12.084 0 012.272-1.677zM12.017 0h.097l.082.001.069.001.054.002.068.002.046.001.076.003.047.002.06.003.054.002.087.005.105.007.144.011.088.007.044.004.077.008.082.008.047.005.102.012.05.006.108.014.081.01.042.006.065.01.207.032.07.012.065.011.14.026.092.018.11.022.046.01.075.016.041.01L14.7.3l.042.01.065.015.049.012.071.017.096.024.112.03.113.03.113.032.05.015.07.02.078.024.073.023.05.016.05.016.076.025.099.033.102.036.048.017.064.023.093.034.11.041.116.045.1.04.047.02.06.024.041.018.063.026.04.018.057.025.11.048.1.046.074.035.075.036.06.028.092.046.091.045.102.052.053.028.049.026.046.024.06.033.041.022.052.029.088.05.106.06.087.051.057.034.053.032.096.059.088.055.098.062.036.024.064.041.084.056.04.027.062.042.062.043.023.017c.054.037.108.075.161.114l.083.06.065.048.056.043.086.065.082.064.04.03.05.041.086.069.079.065.085.071c.712.6 1.353 1.283 1.909 2.031L7.222.994l.062-.027.065-.028.081-.034.086-.035c.113-.045.227-.09.341-.131l.096-.035.093-.033.084-.03.096-.031c.087-.03.176-.058.264-.085l.091-.027.086-.025.102-.03.085-.023.1-.026L9.04.37l.09-.023.091-.022.095-.022.09-.02.098-.021.091-.02.095-.018.092-.018.1-.018.091-.016.098-.017.092-.014.097-.015.092-.013.102-.013.091-.012.105-.012.09-.01.105-.01c.093-.01.186-.018.28-.024l.106-.008.09-.005.11-.006.093-.004.1-.004.097-.002.099-.002.197-.002z"></path></svg>
    """
    
    public init(size: CGFloat = 16) {
        self.size = size
    }
    
    public var body: some View {
        NativeSVGView(svg: Self.svgString, size: size, isTemplate: true)
    }
}

public struct NvidiaLogoView: View {
    public var size: CGFloat = 16
    private static let svgString = """
    <svg height="1em" style="flex:none;line-height:1" viewBox="0 0 24 24" width="1em" xmlns="http://www.w3.org/2000/svg"><title>Nvidia</title><path d="M10.212 8.976V7.62c.127-.01.256-.017.388-.021 3.596-.117 5.957 3.184 5.957 3.184s-2.548 3.647-5.282 3.647a3.227 3.227 0 01-1.063-.175v-4.109c1.4.174 1.681.812 2.523 2.258l1.873-1.627a4.905 4.905 0 00-3.67-1.846 6.594 6.594 0 00-.729.044m0-4.476v2.025c.13-.01.259-.019.388-.024 5.002-.174 8.261 4.226 8.261 4.226s-3.743 4.69-7.643 4.69c-.338 0-.675-.031-1.007-.092v1.25c.278.038.558.057.838.057 3.629 0 6.253-1.91 8.794-4.169.421.347 2.146 1.193 2.501 1.564-2.416 2.083-8.048 3.763-11.24 3.763-.308 0-.603-.02-.894-.048V19.5H24v-15H10.21zm0 9.756v1.068c-3.356-.616-4.287-4.21-4.287-4.21a7.173 7.173 0 014.287-2.138v1.172h-.005a3.182 3.182 0 00-2.502 1.178s.615 2.276 2.507 2.931m-5.961-3.3c1.436-1.935 3.604-3.148 5.961-3.336V6.523C5.81 6.887 2 10.723 2 10.723s2.158 6.427 8.21 7.015v-1.166C5.77 16 4.25 10.958 4.25 10.958h-.002z" fill="#5A8D15" fill-rule="nonzero"></path></svg>
    """
    
    public init(size: CGFloat = 16) {
        self.size = size
    }
    
    public var body: some View {
        NativeSVGView(svg: Self.svgString, size: size, isTemplate: true)
            .scaleEffect(1.25)
    }
}

public struct OllamaLogoView: View {
    public var size: CGFloat = 16
    private static let svgString = """
    <svg fill="currentColor" fill-rule="evenodd" height="1em" style="flex:none;line-height:1" viewBox="0 0 24 24" width="1em" xmlns="http://www.w3.org/2000/svg"><title>Ollama</title><path d="M7.905 1.09c.216.085.411.225.588.41.295.306.544.744.734 1.263.191.522.315 1.1.362 1.68a5.054 5.054 0 012.049-.636l.051-.004c.87-.07 1.73.087 2.48.474.101.053.2.11.297.17.05-.569.172-1.134.36-1.644.19-.52.439-.957.733-1.264a1.67 1.67 0 01.589-.41c.257-.1.53-.118.796-.042.401.114.745.368 1.016.737.248.337.434.769.561 1.287.23.934.27 2.163.115 3.645l.053.04.026.019c.757.576 1.284 1.397 1.563 2.35.435 1.487.216 3.155-.534 4.088l-.018.021.002.003c.417.762.67 1.567.724 2.4l.002.03c.064 1.065-.2 2.137-.814 3.19l-.007.01.01.024c.472 1.157.62 2.322.438 3.486l-.006.039a.651.651 0 01-.747.536.648.648 0 01-.54-.742c.167-1.033.01-2.069-.48-3.123a.643.643 0 01.04-.617l.004-.006c.604-.924.854-1.83.8-2.72-.046-.779-.325-1.544-.8-2.273a.644.644 0 01.18-.886l.009-.006c.243-.159.467-.565.58-1.12a4.229 4.229 0 00-.095-1.974c-.205-.7-.58-1.284-1.105-1.683-.595-.454-1.383-.673-2.38-.61a.653.653 0 01-.632-.371c-.314-.665-.772-1.141-1.343-1.436a3.288 3.288 0 00-1.772-.332c-1.245.099-2.343.801-2.67 1.686a.652.652 0 01-.61.425c-1.067.002-1.893.252-2.497.703-.522.39-.878.935-1.066 1.588a4.07 4.07 0 00-.068 1.886c.112.558.331 1.02.582 1.269l.008.007c.212.207.257.53.109.785-.36.622-.629 1.549-.673 2.44-.05 1.018.186 1.902.719 2.536l.016.019a.643.643 0 01.095.69c-.576 1.236-.753 2.252-.562 3.052a.652.652 0 01-1.269.298c-.243-1.018-.078-2.184.473-3.498l.014-.035-.008-.012a4.339 4.339 0 01-.598-1.309l-.005-.019a5.764 5.764 0 01-.177-1.785c.044-.91.278-1.842.622-2.59l.012-.026-.002-.002c-.293-.418-.51-.953-.63-1.545l-.005-.024a5.352 5.352 0 01.093-2.49c.262-.915.777-1.701 1.536-2.269.06-.045.123-.09.186-.132-.159-1.493-.119-2.73.112-3.67.127-.518.314-.95.562-1.287.27-.368.614-.622 1.015-.737.266-.076.54-.059.797.042zm4.116 9.09c.936 0 1.8.313 2.446.855.63.527 1.005 1.235 1.005 1.94 0 .888-.406 1.58-1.133 2.022-.62.375-1.451.557-2.403.557-1.009 0-1.871-.259-2.493-.734-.617-.47-.963-1.13-.963-1.845 0-.707.398-1.417 1.056-1.946.668-.537 1.55-.849 2.485-.849zm0 .896a3.07 3.07 0 00-1.916.65c-.461.37-.722.835-.722 1.25 0 .428.21.829.61 1.134.455.347 1.124.548 1.943.548.799 0 1.473-.147 1.932-.426.463-.28.7-.686.7-1.257 0-.423-.246-.89-.683-1.256-.484-.405-1.14-.643-1.864-.643zm.662 1.21l.004.004c.12.151.095.37-.056.49l-.292.23v.446a.375.375 0 01-.376.373.375.375 0 01-.376-.373v-.46l-.271-.218a.347.347 0 01-.052-.49.353.353 0 01.494-.051l.215.172.22-.174a.353.353 0 01.49.051zm-5.04-1.919c.478 0 .867.39.867.871a.87.87 0 01-.868.871.87.87 0 01-.867-.87.87.87 0 01.867-.872zm8.706 0c.48 0 .868.39.868.871a.87.87 0 01-.868.871.87.87 0 01-.867-.87.87.87 0 01.867-.872zM7.44 2.3l-.003.002a.659.659 0 00-.285.238l-.005.006c-.138.189-.258.467-.348.832-.17.692-.216 1.631-.124 2.782.43-.128.899-.208 1.404-.237l.01-.001.019-.034c.046-.082.095-.161.148-.239.123-.771.022-1.692-.253-2.444-.134-.364-.297-.65-.453-.813a.628.628 0 00-.107-.09L7.44 2.3zm9.174.04l-.002.001a.628.628 0 00-.107.09c-.156.163-.32.45-.453.814-.29.794-.387 1.776-.23 2.572l.058.097.008.014h.03a5.184 5.184 0 011.466.212c.086-1.124.038-2.043-.128-2.722-.09-.365-.21-.643-.349-.832l-.004-.006a.659.659 0 00-.285-.239h-.004z"></path></svg>
    """
    
    public init(size: CGFloat = 16) {
        self.size = size
    }
    
    public var body: some View {
        NativeSVGView(svg: Self.svgString, size: size, isTemplate: true)
    }
}

public struct ZhipuLogoView: View {
    public var size: CGFloat = 16
    private static let svgString = """
    <svg height="1em" style="flex:none;line-height:1" viewBox="0 0 24 24" width="1em" xmlns="http://www.w3.org/2000/svg"><title>Zhipu</title><path d="M11.991 23.503a.24.24 0 00-.244.248.24.24 0 00.244.249.24.24 0 00.245-.249.24.24 0 00-.22-.247l-.025-.001zM9.671 5.365a1.697 1.697 0 011.099 2.132l-.071.172-.016.04-.018.054c-.07.16-.104.32-.104.498-.035.71.47 1.279 1.186 1.314h.366c1.309.053 2.338 1.173 2.286 2.523-.052 1.332-1.152 2.38-2.478 2.327h-.174c-.715.018-1.274.64-1.239 1.368 0 .124.018.23.053.337.209.373.54.658.96.8.75.23 1.517-.125 1.9-.782l.018-.035c.402-.64 1.17-.96 1.92-.711.854.284 1.378 1.226 1.099 2.167a1.661 1.661 0 01-2.077 1.102 1.711 1.711 0 01-.907-.711l-.017-.035c-.2-.323-.463-.58-.851-.711l-.056-.018a1.646 1.646 0 00-1.954.746 1.66 1.66 0 01-1.065.764 1.677 1.677 0 01-1.989-1.279c-.209-.906.332-1.83 1.257-2.043a1.51 1.51 0 01.296-.035h.018c.68-.071 1.151-.622 1.116-1.333a1.307 1.307 0 00-.227-.693 2.515 2.515 0 01-.366-1.403 2.39 2.39 0 01.366-1.208c.14-.195.21-.444.227-.693.018-.71-.506-1.261-1.186-1.332l-.07-.018a1.43 1.43 0 01-.299-.07l-.05-.019a1.7 1.7 0 01-1.047-2.114 1.68 1.68 0 012.094-1.101zm-5.575 10.11c.26-.264.639-.367.994-.27.355.096.633.379.728.74.095.362-.007.748-.267 1.013-.402.41-1.053.41-1.455 0a1.062 1.062 0 010-1.482zm14.845-.294c.359-.09.738.024.992.297.254.274.344.665.237 1.025-.107.36-.396.634-.756.718-.551.128-1.1-.22-1.23-.781a1.05 1.05 0 01.757-1.26zm-.064-4.39c.314.32.49.753.49 1.206 0 .452-.176.886-.49 1.206-.315.32-.74.5-1.185.5-.444 0-.87-.18-1.184-.5a1.727 1.727 0 010-2.412 1.654 1.654 0 012.369 0zm-11.243.163c.364.484.447 1.128.218 1.691a1.665 1.665 0 01-2.188.923c-.855-.36-1.26-1.358-.907-2.228a1.68 1.68 0 011.33-1.038c.593-.08 1.183.169 1.547.652zm11.545-4.221c.368 0 .708.2.892.524.184.324.184.724 0 1.048a1.026 1.026 0 01-.892.524c-.568 0-1.03-.47-1.03-1.048 0-.579.462-1.048 1.03-1.048zm-14.358 0c.368 0 .707.2.891.524.184.324.184.724 0 1.048a1.026 1.026 0 01-.891.524c-.569 0-1.03-.47-1.03-1.048 0-.579.461-1.048 1.03-1.048zm10.031-1.475c.925 0 1.675.764 1.675 1.706s-.75 1.705-1.675 1.705-1.674-.763-1.674-1.705c0-.942.75-1.706 1.674-1.706zm-2.626-.684c.362-.082.653-.356.761-.718a1.062 1.062 0 00-.238-1.028 1.017 1.017 0 00-.996-.294c-.547.14-.881.7-.752 1.257.13.558.675.907 1.225.783zm0 16.876c.359-.087.644-.36.75-.72a1.062 1.062 0 00-.237-1.019 1.018 1.018 0 00-.985-.301 1.037 1.037 0 00-.762.717c-.108.361-.017.754.239 1.028.245.263.606.377.953.305l.043-.01zM17.19 3.5a.631.631 0 00.628-.64c0-.355-.279-.64-.628-.64a.631.631 0 00-.628.64c0 .355.28.64.628.64zm-10.38 0a.631.631 0 00.628-.64c0-.355-.28-.64-.628-.64a.631.631 0 00-.628.64c0 .355.279.64.628.64zm-5.182 7.852a.631.631 0 00-.628.64c0 .354.28.639.628.639a.63.63 0 00.627-.606l.001-.034a.62.62 0 00-.628-.64zm5.182 9.13a.631.631 0 00-.628.64c0 .355.279.64.628.64a.631.631 0 00.628-.64c0-.355-.28-.64-.628-.64zm10.38.018a.631.631 0 00-.628.64c0 .355.28.64.628.64a.631.631 0 00.628-.64c0-.355-.279-.64-.628-.64zm5.182-9.148a.631.631 0 00-.628.64c0 .354.279.639.628.639a.631.631 0 00.628-.64c0-.355-.28-.64-.628-.64zm-.384-4.992a.24.24 0 00.244-.249.24.24 0 00-.244-.249.24.24 0 00-.244.249c0 .142.122.249.244.249zM11.991.497a.24.24 0 00.245-.248A.24.24 0 0011.99 0a.24.24 0 00-.244.249c0 .133.108.236.223.247l.021.001zM2.011 6.36a.24.24 0 00.245-.249.24.24 0 00-.244-.249.24.24 0 00-.244.249.24.24 0 00.244.249zm0 11.263a.24.24 0 00-.243.248.24.24 0 00.244.249.24.24 0 00.244-.249.252.252 0 00-.244-.248zm19.995-.018a.24.24 0 00-.245.248.24.24 0 00.245.25.24.24 0 00.244-.25.252.252 0 00-.244-.248z" fill="#3859FF" fill-rule="nonzero"></path></svg>
    """
    
    public init(size: CGFloat = 16) {
        self.size = size
    }
    
    public var body: some View {
        NativeSVGView(svg: Self.svgString, size: size, isTemplate: true)
    }
}

@MainActor
@ViewBuilder
public func getProviderIcon(for provider: String, size: CGFloat = 16) -> some View {
    let p = provider.lowercased()
    if p.contains("anthropic") || p.contains("claude") {
        ClaudeLogoView(size: size)
    } else if p.contains("openai") || p.contains("gpt") {
        OpenAILogoView(size: size)
    } else if p.contains("google") || p.contains("gemini") {
        GeminiLogoView(size: size)
    } else if p.contains("deepseek") {
        DeepSeekLogoView(size: size)
    } else if p.contains("x-ai") || p.contains("xai") || p.contains("grok") {
        GrokLogoView(size: size)
    } else if p.contains("nvidia") || p.contains("nemotron") || p.contains("parakeet") {
        NvidiaLogoView(size: size)
    } else if p.contains("qwen") || p.contains("alibaba") {
        QwenLogoView(size: size)
    } else if p.contains("moonshot") || p.contains("kimi") {
        MoonshotLogoView(size: size)
    } else if p.contains("zhipu") || p.contains("z-ai") || p.contains("glm") {
        ZhipuLogoView(size: size)
    } else if p.contains("minimax") {
        MiniMaxLogoView(size: size)
    } else if p.contains("meta") || p.contains("llama") {
        MetaLogoView(size: size)
    } else if p.contains("mistral") {
        MistralLogoView(size: size)
    } else if p.contains("groq") {
        GroqLogoView(size: size)
    } else if p.contains("elevenlabs") || p.contains("scribe") {
        ElevenLabsLogoView(size: size)
    } else if p.contains("ollama") {
        OllamaLogoView(size: size)
    } else if p.contains("huggingface") || p.contains("hf") {
        HuggingFaceLogoView(size: size)
    } else if p.contains("deepgram") || p.contains("nova") {
        DeepgramLogoView(size: size)
    } else if p.contains("apple") || p.contains("mac") {
        AppleLogoView(size: size)
    } else {
        // Fallback
        Image(systemName: "cpu")
            .font(.system(size: size))
    }
}

public struct DeepgramLogoView: View {
    public var size: CGFloat = 16
    public var isTemplate: Bool = true
    private static let svgString = """
    <svg fill="#000000" role="img" viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg"><title>Deepgram</title><path d="M11.203 24H1.517a.364.364 0 0 1-.258-.62l6.239-6.275a.366.366 0 0 1 .259-.108h3.52c2.723 0 5.025-2.127 5.107-4.845a5.004 5.004 0 0 0-4.999-5.148H7.613v4.646c0 .2-.164.364-.365.364H.968a.365.365 0 0 1-.363-.364V.364C.605.164.768 0 .969 0h10.416c6.684 0 12.111 5.485 12.01 12.187C23.293 18.77 17.794 24 11.202 24z"/></svg>
    """
    
    public init(size: CGFloat = 16, isTemplate: Bool = true) {
        self.size = size
        self.isTemplate = isTemplate
    }
    
    public var body: some View {
        NativeSVGView(svg: Self.svgString, size: size, isTemplate: isTemplate)
    }
}

public struct AppleLogoView: View {
    public var size: CGFloat = 16
    private static let svgString = """
    <svg fill="currentColor" fill-rule="evenodd" height="1em" style="flex:none;line-height:1" viewBox="0 0 24 24" width="1em" xmlns="http://www.w3.org/2000/svg"><title>Apple</title><path d="M11.932 6.908c.95 0 2.727-1.291 4.595-1.1.782.032 2.976.316 4.388 2.38-.113.069-2.622 1.528-2.593 4.565.034 3.617 3.166 4.828 3.221 4.85-.029.086-.506 1.723-1.658 3.416-1.002 1.463-2.039 2.919-3.675 2.95-1.606.03-2.125-.955-3.96-.955s-2.409.923-3.931.984c-1.581.06-2.78-1.58-3.79-3.037-2.065-2.98-3.64-8.422-1.527-12.087 1.051-1.824 2.93-2.98 4.969-3.009 1.549-.032 3.011 1.043 3.96 1.043zM16.552 0c.153 1.407-.411 2.817-1.251 3.833-.837 1.013-2.214 1.804-3.555 1.7-.185-1.378.495-2.814 1.27-3.712C13.883.805 15.346.05 16.553 0z"></path></svg>
    """
    
    public init(size: CGFloat = 16) {
        self.size = size
    }
    
    public var body: some View {
        NativeSVGView(svg: Self.svgString, size: size, isTemplate: true)
    }
}

public struct MistralLogoView: View {
    public var size: CGFloat = 16
    private static let svgString = """
    <svg height="1em" style="flex:none;line-height:1" viewBox="0 0 24 24" width="1em" xmlns="http://www.w3.org/2000/svg"><title>Mistral</title><path d="M3.428 3.4h3.429v3.428H3.428V3.4zm13.714 0h3.43v3.428h-3.43V3.4z" fill="gold"></path><path d="M3.428 6.828h6.857v3.429H3.429V6.828zm10.286 0h6.857v3.429h-6.857V6.828z" fill="#FFAF00"></path><path d="M3.428 10.258h17.144v3.428H3.428v-3.428z" fill="#FF8205"></path><path d="M3.428 13.686h3.429v3.428H3.428v-3.428zm6.858 0h3.429v3.428h-3.429v-3.428zm6.856 0h3.43v3.428h-3.43v-3.428z" fill="#FA500F"></path><path d="M0 17.114h10.286v3.429H0v-3.429zm13.714 0H24v3.429H13.714v-3.429z" fill="#E10500"></path></svg>
    """
    
    public init(size: CGFloat = 16) {
        self.size = size
    }
    
    public var body: some View {
        NativeSVGView(svg: Self.svgString, size: size, isTemplate: true)
    }
}

public struct ClaudeLogoView: View {
    public var size: CGFloat = 16
    private static let svgString = """
    <svg height="1em" style="flex:none;line-height:1" viewBox="0 0 24 24" width="1em" xmlns="http://www.w3.org/2000/svg"><title>Claude</title><path d="M4.709 15.955l4.72-2.647.08-.23-.08-.128H9.2l-.79-.048-2.698-.073-2.339-.097-2.266-.122-.571-.121L0 11.784l.055-.352.48-.321.686.06 1.52.103 2.278.158 1.652.097 2.449.255h.389l.055-.157-.134-.098-.103-.097-2.358-1.596-2.552-1.688-1.336-.972-.724-.491-.364-.462-.158-1.008.656-.722.881.06.225.061.893.686 1.908 1.476 2.491 1.833.365.304.145-.103.019-.073-.164-.274-1.355-2.446-1.446-2.49-.644-1.032-.17-.619a2.97 2.97 0 01-.104-.729L6.283.134 6.696 0l.996.134.42.364.62 1.414 1.002 2.229 1.555 3.03.456.898.243.832.091.255h.158V9.01l.128-1.706.237-2.095.23-2.695.08-.76.376-.91.747-.492.584.28.48.685-.067.444-.286 1.851-.559 2.903-.364 1.942h.212l.243-.242.985-1.306 1.652-2.064.73-.82.85-.904.547-.431h1.033l.76 1.129-.34 1.166-1.064 1.347-.881 1.142-1.264 1.7-.79 1.36.073.11.188-.02 2.856-.606 1.543-.28 1.841-.315.833.388.091.395-.328.807-1.969.486-2.309.462-3.439.813-.042.03.049.061 1.549.146.662.036h1.622l3.02.225.79.522.474.638-.079.485-1.215.62-1.64-.389-3.829-.91-1.312-.329h-.182v.11l1.093 1.068 2.006 1.81 2.509 2.33.127.578-.322.455-.34-.049-2.205-1.657-.851-.747-1.926-1.62h-.128v.17l.444.649 2.345 3.521.122 1.08-.17.353-.608.213-.668-.122-1.374-1.925-1.415-2.167-1.143-1.943-.14.08-.674 7.254-.316.37-.729.28-.607-.461-.322-.747.322-1.476.389-1.924.315-1.53.286-1.9.17-.632-.012-.042-.14.018-1.434 1.967-2.18 2.945-1.726 1.845-.414.164-.717-.37.067-.662.401-.589 2.388-3.036 1.44-1.882.93-1.086-.006-.158h-.055L4.132 18.56l-1.13.146-.487-.456.061-.746.231-.243 1.908-1.312-.006.006z" fill="#D97757" fill-rule="nonzero"></path></svg>
    """
    
    public init(size: CGFloat = 16) {
        self.size = size
    }
    
    public var body: some View {
        NativeSVGView(svg: Self.svgString, size: size, isTemplate: true)
    }
}

public struct GeminiLogoView: View {
    public var size: CGFloat = 16
    private static let svgString = """
    <svg height="1em" style="flex:none;line-height:1" viewBox="0 0 24 24" width="1em" xmlns="http://www.w3.org/2000/svg"><title>Gemini</title><path d="M12 0C12 6.5 6.5 12 0 12C6.5 12 12 17.5 12 24C12 17.5 17.5 12 24 12C17.5 12 12 6.5 12 0Z" fill="#3186FF"></path></svg>
    """
    
    public init(size: CGFloat = 16) {
        self.size = size
    }
    
    public var body: some View {
        NativeSVGView(svg: Self.svgString, size: size, isTemplate: true)
            .scaleEffect(1.5)
    }
}
