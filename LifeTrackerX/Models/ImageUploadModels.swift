import Foundation

struct ImageUploadResponse: Codable {
    let success: Bool
    let id: Int?
    let user_id: Int?
    let image_type_id: Int?
    let uploaded_at: String?
    let deleted: Bool?
    let message: String?
    let error: String?
    let showToast: Bool?
}

struct ImagesListResponse: Codable {
    let success: Bool
    let images: [ImageMeta]
    let total: Int
    let error: String?
}

struct ImageMeta: Codable {
    let id: String
    let image_type_id: Int
    let filename: String?
    let date: String
    let file_size: Int?
    let mime_type: String?
}

struct BasicResponse: Codable {
    let success: Bool
    let message: String?
    let error: String?
}


