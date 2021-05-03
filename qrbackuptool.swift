// QRBackupTool
//
// Copyright (c) 2021 Leszek S
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.

import Foundation
import CoreImage
import Vision
import zlib

struct Config {
    static let fileToEncode: String? = CommandLine.extParameters["-e"]
    static let encodingCorrectionLevel: String = CommandLine.extParameters["-c"] ?? "L"
    static let listFileToDecode: String? = CommandLine.extParameters["-d"]
    static let codesFileToDecode: String? = CommandLine.extParameters["-s"]
    static let maxCodesOnImage: Int? = Int(CommandLine.extParameters["-m"] ?? "")
    static let encodingPageWidth: Int? = Int(CommandLine.extParameters["-t"]?.split(separator: "x").first ?? "")
    static let encodingPageHeight: Int? = Int(CommandLine.extParameters["-t"]?.split(separator: "x").last ?? "")
}

print("""

QRBackupTool v1.0.0
Copyright (c) 2021 Leszek S

""")

if (Config.fileToEncode == nil && Config.listFileToDecode == nil && Config.codesFileToDecode == nil) ||
    (Config.fileToEncode != nil && (Config.listFileToDecode != nil || Config.codesFileToDecode != nil)) ||
    ((Config.maxCodesOnImage ?? 0) < 0) ||
    ((Config.encodingPageWidth ?? 1) < 1) ||
    ((Config.encodingPageHeight ?? 1) < 1) ||
    (!["L", "M", "Q", "H"].contains(Config.encodingCorrectionLevel)) {
    print("""
        This tool allows to convert any file to a set of QR barcode images and also
        convert a set of QR barcode images back to the original file. The purpose of
        doing that is to create a backup of important data on a paper by printing
        generated images and scanning them later.

        Usage: qrbackuptool [option] <file>

        Options:
            -e <file>           - Encode given file to images with QR barcode
            -c <file>           - Encoding correction level (choose from: L, M, Q, H)
            -t <size>           - Generate images with multiple QR barcodes per image
                                  for printing on paper (example size: 4x5)
            -d <list file>      - Decode QR barcode images listed in a file with paths
            -s <codes file>     - Decode already scanned codes saved in given text file
            -m <integer value>  - Maximum number of QR barcodes on an image while
                                  decoding (optional, speeds up decoding by moving to
                                  a next image when given number of QR barcodes found)

        Example usage:
            qrbackuptool -e /Users/john/test.zip -t 4x5
            qrbackuptool -d /Users/john/list.txt -m 20
            qrbackuptool -s /Users/john/codes.txt
            qrbackuptool -d /Users/john/list.txt -s /Users/john/codes.txt -m 20

        Example list.txt for decoding:
            /Users/john/qr_image_1.png
            /Users/john/qr_image_2.png
            /Users/john/qr_image_3.png

        Example codes.txt for decoding:
            LSQRBTYQAAAAACIAAAABOAAAAB5GCLTKOBTQAJETGETFSXL6MVTH...
            LSQRBTYQAAAAAAQAAAABOAAAAB5GCLTKOBTQA5U5OFYO3BMGGL4R...
            LSQRBTYQAAAAACQAAAABOAAAAB5GCLTKOBTQBPORM63NGAMTMQXS...
        
        Notes:
            - Each generated QR barcode contains additional metadata including index
              and total number of parts so QR barcodes can be listed in decoding files
              in random order and with random file names and still be decoded properly.
            - Original encoded file name is also stored in the metadata and is used
              when file is decoded later.
            - List file for decoding of many images can be generetad with unix commands
              for example with ls command: ls -d "$PWD/"qr*.png > list.txt
            - Images used for decoding can contain multipe QR barcodes so you can pass
              for example an image with scanned A4 page with many QR barcodes on it.
            - You can use any mobile app for QR barcode scanning, save scanned codes to
              text file and decode from that instead of decoding from image files. You
              can mix both decoding modes, duplicates will be automatically detected.

        """)
    exit(0)
}

let fileToEncodeUrl = Config.fileToEncode.map({ URL(fileURLWithPath: $0) })
let listFileToDecodeUrl = Config.listFileToDecode.map({ URL(fileURLWithPath: $0) })
let codesFileToDecodeUrl = Config.codesFileToDecode.map({ URL(fileURLWithPath: $0) })

if let fileToEncodeUrl = fileToEncodeUrl {
    encode(fileToEncodeUrl: fileToEncodeUrl)
} else if listFileToDecodeUrl != nil || codesFileToDecodeUrl != nil {
    decode(listFileToDecodeUrl: listFileToDecodeUrl, codesFileToDecodeUrl: codesFileToDecodeUrl)
}

exit(0)

func encode(fileToEncodeUrl: URL) {
    guard let fileData = try? Data(contentsOf: fileToEncodeUrl) else {
        print("Error: Could not read file to encode at given path.")
        exit(1)
    }
    
    let fileName = fileToEncodeUrl.lastPathComponent
    let fileNameWithoutExtension = fileToEncodeUrl.deletingPathExtension().lastPathComponent
    let checksum = UInt32(fileData.withUnsafeBytes { crc32(0, $0.bindMemory(to: Bytef.self).baseAddress, uInt(fileData.count)) })
    let destinationDirectoryUrl = fileToEncodeUrl.deletingLastPathComponent()
    
    guard var lsqrbtCode = LSQRBTCode(fileName: fileName, checksum: checksum) else {
        print("Error: Cound not prepare code.")
        exit(1)
    }
    
    let sizesForCorrectionLevels = ["L": 2680, "M": 2115, "Q": 1510, "H": 1155]
    guard let partTotalSize = sizesForCorrectionLevels[Config.encodingCorrectionLevel] else {
        print("Error: Invalid encoding correction level.")
        exit(1)
    }
    
    let partBodySize = partTotalSize - Int(lsqrbtCode.size)

    var partsIndex = 0
    var partsCount = fileData.count / partBodySize
    let lastPartBodySize = (fileData.count == partsCount * partBodySize) ? partBodySize : (fileData.count - partsCount * partBodySize)
    let lastPartPaddingSize = (lastPartBodySize == partBodySize) ? 0 : (partBodySize - lastPartBodySize)
    
    partsCount = partsCount + (lastPartBodySize == partBodySize ? 0 : 1)
    lsqrbtCode.count = UInt32(partsCount)
    
    print("Encoding file: \"\(fileName)\" (size: \(fileData.count), crc32: 0x\(String(format:"%08X", checksum)))")
    print("Correction level: \(Config.encodingCorrectionLevel) \(Config.encodingCorrectionLevel == "L" ? "(Default)" : "")")
    print("Number of parts: \(partsCount)\n")
    
    var savedImageFilesUrls = [URL]()
    
    while partsIndex < partsCount {
        autoreleasepool {
            let part: Data
            
            if partsIndex == partsCount - 1 {
                part = fileData.subdata(in: partsIndex * partBodySize ..< partsIndex * partBodySize + lastPartBodySize)
                lsqrbtCode.padding = lastPartPaddingSize
            } else {
                part = fileData.subdata(in: partsIndex * partBodySize ..< partsIndex * partBodySize + partBodySize)
            }
            
            lsqrbtCode.index = UInt32(partsIndex)
            
            lsqrbtCode.body = part
            
            let finalData = lsqrbtCode.encoded()
            
            guard let finalDataEncoded = finalData.extBase32EncodedData() else {
                print("Error: Cound not encode data.")
                exit(1)
            }
            
            let indexFormatted = String(format: "%0\(String(partsCount).count)d", partsIndex + 1)
            let imageTitle = " \(fileName) (\(indexFormatted) / \(partsCount))"
            let imageFileName = "lsqrbt_\(indexFormatted)_\(partsCount)_\(fileNameWithoutExtension).png"
            let imageFileUrl = destinationDirectoryUrl.appendingPathComponent(imageFileName)
            
            guard let qrBarcodeImage = generateQrBarcode(from: finalDataEncoded, title: imageTitle) else {
                print("Error: Cound not generate QR barcode image.")
                exit(1)
            }
            
            guard saveToPngFile(image: qrBarcodeImage, fileUrl: imageFileUrl) else {
                print("Error: Cound not save png file.")
                exit(1)
            }
            
            partsIndex += 1
            savedImageFilesUrls.append(imageFileUrl)
            print("Generated \"\(imageFileName)\" [\(100 * partsIndex / partsCount)%]")
        }
    }
    
    if let pageWidth = Config.encodingPageWidth, let pageHeight = Config.encodingPageHeight {
        var xPos = 0
        var yPos = 0
        var page = 0
        var pageImage = CIImage()
        let pagesCount = savedImageFilesUrls.count / (pageWidth * pageHeight) + 1
        print("Generating \(pagesCount) page(s) for printing (width: \(pageWidth), height: \(pageHeight))")
        for savedImageFileUrl in savedImageFilesUrls {
            autoreleasepool {
                var savePage = savedImageFilesUrls.last == savedImageFileUrl
                if page == 8 {
                    
                }
                if let image = CIImage(contentsOf: savedImageFileUrl) {
                    let translatedImage = image.transformed(by: CGAffineTransform(translationX: (image.extent.width + 100) * CGFloat(xPos), y:image.extent.height * CGFloat(pageHeight - 1 - yPos)))
                    pageImage = pageImage.composited(over: translatedImage)
                }
                
                xPos += 1
                if xPos >= pageWidth {
                    xPos = 0
                    yPos += 1
                    if yPos >= pageHeight {
                        yPos = 0
                        savePage = true
                    }
                }
                
                if savePage {
                    let pageFormatted = String(format: "%0\(String(pagesCount).count)d", page + 1)
                    let imageFileName = "lsqrbt_page_\(pageFormatted)_\(pagesCount)_\(fileNameWithoutExtension).png"
                    let imageFileUrl = destinationDirectoryUrl.appendingPathComponent(imageFileName)
                    
                    let bgImg = CIImage(color: .white)
                    let img = pageImage.composited(over: bgImg).cropped(to: CGRect(x: pageImage.extent.origin.x, y: pageImage.extent.origin.y, width: pageImage.extent.size.width, height: pageImage.extent.size.height))
                    
                    guard saveToPngFile(image: img, fileUrl: imageFileUrl) else {
                        print("Error: Cound not save png file.")
                        exit(1)
                    }
                    
                    page += 1
                    print("Generated \(imageFileName)")
                    pageImage = CIImage()
                }
            }
        }
    }
    
    print("Encoding finished!")
}

func decode(listFileToDecodeUrl: URL?, codesFileToDecodeUrl: URL?) {
    var listFileData: Data? = nil
    var codesFileData: Data? = nil
    var destinationDirectoryUrl: URL? = nil
    
    if let listFileToDecodeUrl = listFileToDecodeUrl {
        guard let fileData = try? Data(contentsOf: listFileToDecodeUrl) else {
            print("Error: Could not read list file at given path.")
            exit(1)
        }
        listFileData = fileData
        destinationDirectoryUrl = listFileToDecodeUrl.deletingLastPathComponent()
    }
    
    if let codesFileToDecodeUrl = codesFileToDecodeUrl {
        guard let fileData = try? Data(contentsOf: codesFileToDecodeUrl) else {
            print("Error: Could not read codes file at given path.")
            exit(1)
        }
        codesFileData = fileData
        destinationDirectoryUrl = codesFileToDecodeUrl.deletingLastPathComponent()
    }
    
    guard let destinationDirectory = destinationDirectoryUrl else {
        print("Error: Could not read any file for decoding.")
        exit(1)
    }
    
    let detectedLsqrbtCodesFromListFile = detectLsqrbtCodes(listFileData: listFileData)
    
    print("Detected \(detectedLsqrbtCodesFromListFile.count) code(s) from list file.")
    
    let detectedLsqrbtCodesFromCodesFile = detectLsqrbtCodes(codesFileData: codesFileData)
    
    print("Detected \(detectedLsqrbtCodesFromCodesFile.count) code(s) from codes file.")
    
    var detectedLsqrbtCodes = detectedLsqrbtCodesFromListFile
    detectedLsqrbtCodes.append(contentsOf: detectedLsqrbtCodesFromCodesFile)
    detectedLsqrbtCodes = Array(Set(detectedLsqrbtCodes))
    
    print("Detected \(detectedLsqrbtCodes.count) unique code(s) in total.")
    
    var fileIdentifiers: [String: [LSQRBTCode]] = [:]
    
    for detectedLsqrbtCode in detectedLsqrbtCodes {
        if let decodedData = detectedLsqrbtCode.data(using: .utf8)?.extBase32DecodedData(), let lsqrbtCode = LSQRBTCode(data: decodedData) {
            let fileIdentifier = "\(lsqrbtCode.fileName) \(String(format:"%08X", lsqrbtCode.checksum))"
            var lsqrbtCodes = fileIdentifiers[fileIdentifier] ?? []
            lsqrbtCodes.append(lsqrbtCode)
            fileIdentifiers[fileIdentifier] = lsqrbtCodes
        }
    }
    
    for fileIdentifier in fileIdentifiers {
        print("Found \(fileIdentifier.value.count) parts of file \(fileIdentifier.key).")
    }
    
    for fileIdentifier in fileIdentifiers {
        var lsqrbtCodes = fileIdentifier.value
        lsqrbtCodes.sort { first, second -> Bool in
            return first.index < second.index
        }
        guard Set(lsqrbtCodes.map({ $0.count })).count == 1, let count = lsqrbtCodes.first?.count, let fileName = lsqrbtCodes.first?.fileName, let checksum = lsqrbtCodes.first?.checksum else {
            print("Error: Detected conflicted data for file \(fileIdentifier.key)")
            exit(1)
        }
        let foundIndexes = Set(lsqrbtCodes.map({ $0.index }))
        let expectedIndexes = Array(0 ..< count)
        var missingIndexes = expectedIndexes
        missingIndexes.removeAll(where: { foundIndexes.contains($0) })
        guard missingIndexes.isEmpty else {
            print("Error: Could not read \(missingIndexes.count) parts of file \(fileIdentifier.key). Missing parts: \(missingIndexes) (found parts: \(foundIndexes))")
            exit(0)
        }
        var decodedFileData = Data()
        for index in 0 ..< count {
            let lsqrbtCode = lsqrbtCodes.first(where: { $0.index == index })!
            decodedFileData.append(lsqrbtCode.body)
        }
        
        let destination = destinationDirectory.appendingPathComponent("lsqrbt_\(fileName)")
        
        do {
            try decodedFileData.write(to: destination)
        } catch {
            print("Error: Cound not save decoded file \(fileIdentifier.key).")
            exit(1)
        }
        
        print("Decoded \(fileIdentifier.key) and saved to \(destination).")
        
        let decodedFileDataChecksum = UInt32(decodedFileData.withUnsafeBytes { crc32(0, $0.bindMemory(to: Bytef.self).baseAddress, uInt(decodedFileData.count)) })
        if checksum != decodedFileDataChecksum {
            print("Error: Decoded file \(fileIdentifier.key) has invalid checksum! File corrupted!")
            exit(1)
        }
        print("Checksum validated successfully.")
    }
    
    print("Decoding finished!")
}

func generateQrBarcode(from data: Data, title: String) -> CIImage? {
    let qrGeneratorFilter = CIFilter(name: "CIQRCodeGenerator")
    qrGeneratorFilter?.setValue(data, forKey: "inputMessage")
    qrGeneratorFilter?.setValue(Config.encodingCorrectionLevel, forKey: "inputCorrectionLevel")
    
    let textGeneratorFilter = CIFilter(name: "CITextImageGenerator")
    textGeneratorFilter?.setValue(title, forKey: "inputText")
    textGeneratorFilter?.setValue(80, forKey: "inputFontSize")
    
    if let qrImage = qrGeneratorFilter?.outputImage, let titleImage = textGeneratorFilter?.outputImage {
        let qrImg = qrImage.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        let bgImg = CIImage(color: .white)
        let titleImg = titleImage.composited(over: bgImg).cropped(to: CGRect(x: 0, y: 0, width: Int(qrImg.extent.width), height: 100))
        let img = titleImg.transformed(by: CGAffineTransform(translationX: 0, y: qrImg.extent.height)).composited(over: qrImg)
        return img
    }
    return nil
}

func saveToPngFile(image: CIImage, fileUrl: URL) -> Bool {
    guard let pngData = CIContext().pngRepresentation(of: image, format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB()) else {
        return false
    }
    do {
        try pngData.write(to: fileUrl)
    } catch {
        return false
    }
    return true
}

func detectLsqrbtCodes(codesFileData: Data?) -> [String] {
    guard let codesFileData = codesFileData else {
        return []
    }
    let codesFileLines = String(data: codesFileData, encoding: .utf8)?.split(separator: "\n") ?? []
    
    var detectedCodes: [String] = []
    
    for codesFileLine in codesFileLines {
        let line = codesFileLine.trimmingCharacters(in: .whitespacesAndNewlines)
        if line.hasPrefix("LSQRBT") {
            detectedCodes.append(line)
            print("Detected code from codes file:\n\(line))\n")
        }
    }
    
    return detectedCodes
}

func detectLsqrbtCodes(listFileData: Data?) -> [String] {
    guard let listFileData = listFileData else {
        return []
    }
    
    let imageFilesUrls = String(data: listFileData, encoding: .utf8)?.split(separator: "\n").map({ URL(fileURLWithPath:String($0)) }) ?? []
    
    var detectedCodes: [String] = []
    
    for imageFileUrl in imageFilesUrls {
        autoreleasepool {
            if let image = CIImage(contentsOf: imageFileUrl) {
                print("Detecting QR barcode(s) on \(imageFileUrl.lastPathComponent)")
                let detectedQrBarcodes = detectQrBarcodes(image: image)
                print("Detected \(detectedQrBarcodes.count) QR barcode(s) on \(imageFileUrl.lastPathComponent).")
                for detectedQrBarcode in detectedQrBarcodes {
                    if detectedQrBarcode.hasPrefix("LSQRBT") {
                        detectedCodes.append(detectedQrBarcode)
                        print("Detected code from list file:\n\(detectedQrBarcode)\n")
                    }
                }
            } else {
                print("Error: Could not read image from file \(imageFileUrl.lastPathComponent).")
            }
        }
    }
    
    return detectedCodes
}

func detectQrBarcodes(image: CIImage) -> [String] {
    var detectedQrBarcodes = [String]()
    let maxNumberOfQrBarcodes = Config.maxCodesOnImage ?? 0
    let imageRotated = image.oriented(.down)
    for contrast in stride(from: 1.0, through: 3.0, by: 0.5) {
        for exposure in stride(from: 0.0, through: 2.0, by: 0.5) {
            for img in [image, imageRotated] {
                let adjustedImage = adjustImage(image: img, exposure: exposure, contrast: contrast)
                let qrBarcodes = readQrBarcodes(image: adjustedImage)
                detectedQrBarcodes.append(contentsOf: qrBarcodes)
                print("Detected \(Array(Set(detectedQrBarcodes)).count) (c: \(contrast), e: \(exposure), r: \(img == imageRotated))")
                if maxNumberOfQrBarcodes > 0 && (Array(Set(detectedQrBarcodes)).count == maxNumberOfQrBarcodes) {
                    return Array(Set(detectedQrBarcodes))
                }
            }
        }
    }
    
    return Array(Set(detectedQrBarcodes))
}

func adjustImage(image: CIImage, exposure: Double?, contrast: Double?) -> CIImage {
    var adjustedImage = image
    if let exposure = exposure, let exposureFilter = CIFilter(name: "CIExposureAdjust") {
        exposureFilter.setValue(adjustedImage, forKey: "inputImage")
        exposureFilter.setValue(exposure, forKey: "inputEV")
        adjustedImage = exposureFilter.outputImage ?? adjustedImage
    }
    if let contrast = contrast, let colorFilter = CIFilter(name: "CIColorControls") {
        colorFilter.setValue(adjustedImage, forKey: "inputImage")
        colorFilter.setValue(contrast, forKey: "inputContrast")
        adjustedImage = colorFilter.outputImage ?? adjustedImage
    }
    return adjustedImage
}

func readQrBarcodes(image: CIImage) -> [String] {
    var qrBarcodes = [String]()
    let barcodeRequest = VNDetectBarcodesRequest(completionHandler: {(request, error) in
        for result in request.results ?? [] {
            if let barcode = result as? VNBarcodeObservation, let barcodeString = barcode.payloadStringValue {
                qrBarcodes.append(barcodeString)
            }
        }
    })
    let handler = VNImageRequestHandler(ciImage: image, options: [:])
    try? handler.perform([barcodeRequest])
    return qrBarcodes
}

struct LSQRBTCode {
    let header: [UInt8] = [0x5C, 0xA1, 0x10, 0xCF]
    let checksum: UInt32
    var size: UInt32 {
        return UInt32(encoded().count)
    }
    var count: UInt32 = 0
    var index: UInt32 = 0
    let fileName: String
    var padding: Int = 0
    var body: Data = Data()
    
    init?(fileName: String, checksum: UInt32) {
        guard fileName.count > 0 else {
            return nil
        }
        self.fileName = fileName
        self.checksum = checksum
    }
    
    func encoded() -> Data {
        var data = Data()
        let name = fileName.utf8.map { UInt8($0) }
        let size = 4 + 4 + 4 + 4 + 4 + UInt32(name.count) + 1 + UInt32(padding)
        data.append(contentsOf: header)
        data.append(checksum.extLittleEndianData())
        data.append(size.extLittleEndianData())
        data.append(count.extLittleEndianData())
        data.append(index.extLittleEndianData())
        data.append(contentsOf: name)
        data.append(0)
        data.append(Data(repeating: 0, count: padding))
        data.append(body)
        return data
    }
    
    init?(data: Data) {
        guard data.count >= 4 + 4 + 4 + 4 + 4 + 1 + 1,
            data.subdata(in: 0 ..< 4) == Data(header),
            let checksum = UInt32(extLittleEndianData: data.subdata(in: 4 ..< 8)),
            let size = UInt32(extLittleEndianData: data.subdata(in: 8 ..< 12)),
            let count = UInt32(extLittleEndianData: data.subdata(in: 12 ..< 16)),
            let index = UInt32(extLittleEndianData: data.subdata(in: 16 ..< 20)),
            size >= 4 + 4 + 4 + 4 + 4 + 1 + 1,
            data.count >= size,
            data[20] != 0,
            data[Int(size) - 1] == 0
        else {
            print("Error: Invalid code data.")
            return nil
        }
        
        self.checksum = checksum
        self.count = count
        self.index = index
        
        let fileNameAndPadding = data.subdata(in: 20 ..< Int(size))
        fileName = String(cString: Array(fileNameAndPadding))
        padding = fileNameAndPadding.count - fileName.count
        body = data.subdata(in: Int(size) ..< data.count)
    }
}

extension UInt32 {
    func extLittleEndianData() -> Data {
        return Data([UInt8(self & 0xFF), UInt8((self >> 8) & 0xFF), UInt8((self >> 16) & 0xFF), UInt8((self >> 24) & 0xFF)])
    }
    
    init?(extLittleEndianData data: Data) {
        guard data.count == 4 else {
            return nil
        }
        self = (UInt32(data[3]) << 24) | (UInt32(data[2]) << 16) | (UInt32(data[1]) << 8) | UInt32(data[0])
    }
}

extension Data {
    func extBase32EncodedData() -> Data? {
        guard let transform = SecEncodeTransformCreate(kSecBase32Encoding, nil) else {
            return nil
        }
        SecTransformSetAttribute(transform, kSecTransformInputAttributeName, self as NSData, nil)
        return SecTransformExecute(transform, nil) as? Data
    }
    
    func extBase32DecodedData() -> Data? {
        guard let transform = SecDecodeTransformCreate(kSecBase32Encoding, nil) else {
            return nil
        }
        SecTransformSetAttribute(transform, kSecTransformInputAttributeName, self as NSData, nil)
        return SecTransformExecute(transform, nil) as? Data
    }
}

extension CommandLine {
    static var extParameters: [String: String] {
        var parameters = [String: String]()
        for i in 0 ..< arguments.count {
            if arguments[i].hasPrefix("-") {
                if (i + 1) < arguments.count && !arguments[i + 1].hasPrefix("-") {
                    parameters[arguments[i]] = arguments[i + 1]
                } else {
                    parameters[arguments[i]] = ""
                }
            }
        }
        return parameters
    }
}
