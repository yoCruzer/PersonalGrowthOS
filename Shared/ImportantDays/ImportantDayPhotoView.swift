import SwiftUI
import UIKit

/// Continuous normalized focal point shared by editor preview and Widget photo background.
struct ImportantDayPhotoView: View {
    let image: UIImage
    let cropX: Double
    let cropY: Double
    var body: some View {
        GeometryReader { geometry in
            let width = max(image.size.width, 1), height = max(image.size.height, 1)
            let scale = max(geometry.size.width / width, geometry.size.height / height)
            let renderedWidth = width * scale, renderedHeight = height * scale
            Image(uiImage: image).resizable()
                .frame(width: renderedWidth, height: renderedHeight)
                .position(x: geometry.size.width / 2 + (0.5 - min(1, max(0, cropX))) * (renderedWidth - geometry.size.width),
                          y: geometry.size.height / 2 + (0.5 - min(1, max(0, cropY))) * (renderedHeight - geometry.size.height))
        }.clipped()
    }
}
