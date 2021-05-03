# QRBackupTool

QRBackupTool is a command line tool that allows to convert any file to a set of QR barcode images and also convert a set of QR barcode images back to the original file. The purpose of doing that is to create a backup of important data on a paper by printing generated images and scanning them later. QRBackupTool is currently available only for macOS.

# Usage
```
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
```

# Notes

QRBackupTool store around 2,6KB of binary data in a single QR barcode with default settings. The file that you want to encode of course can be much bigger and in such case many QR barcodes will be generated and you can print more than one on A4 page. If you need to encode more than one file you can always compress them to a single file and encode that compressed file. Recommended amount of barcodes for printing on A4 page is 20 (use command line option: `-t 4x5`) which gives around 50 KB of binary data on A4 paper page. This setting should allow to decode the file later from scanned images printed with a common home ink printer without problems. During tests maximum amount of successfully recovered data from a single A4 page was around 90 KB (`-t 5x7`) when generated image was printed on a common ink printer. However that required to scan few QR barcodes with mobile phone and use additional codes file option therefore it is not recommend unless you have a good laser printer and a good scanner.

## License
QRBackupTool is available under the MIT license.
