// Run any SwiftUI view as a Mac app.
if CommandLine.arguments.count <= 1 {exit(1);}
import AppKit
import SwiftUI
import AVFoundation

let queue = DispatchQueue.global(qos: .utility)

let url = URL(fileURLWithPath: CommandLine.arguments[1])

func audioFileInfo(_ url: URL) -> NSDictionary? {
    var fileID: AudioFileID? = nil
    var status:OSStatus = AudioFileOpenURL(url as CFURL, .readPermission, kAudioFileFLACType, &fileID)

    guard status == noErr else { return nil }

    var dict: CFDictionary? = nil
    var dataSize = UInt32(MemoryLayout<CFDictionary?>.size(ofValue: dict))

    guard let audioFile = fileID else { return nil }

    status = AudioFileGetProperty(audioFile, kAudioFilePropertyInfoDictionary, &dataSize, &dict)

    guard status == noErr else { return nil }

    AudioFileClose(audioFile)

    guard let cfDict = dict else { return nil }

    let tagsDict = NSDictionary.init(dictionary: cfDict)

    return tagsDict
}

let fileInfo = audioFileInfo(url);

struct AudioInfo{
    init(_ key: String, _ value: String){
        self.key = key;
        self.value = value
    }
    let key: String
    let value: String
}
var ainfos: Array<AudioInfo> = []
if fileInfo != nil {
    ainfos = [
        AudioInfo("題", fileInfo!["title"] as? String ?? "Not found"),
        AudioInfo("輯", fileInfo!["album"] as? String ?? "Not found"),
        AudioInfo("歌", fileInfo!["artist"] as? String ?? "Not found")
    ]
}


var player:AVAudioPlayer!
do{
    player = try AVAudioPlayer(contentsOf:url)
}catch{
    exit(1);
}
player.play()

NSApplication.shared.run{
    MainView()
}


struct MainView: View {
    static func descriptTimeInterval(_ value: TimeInterval)->String{
        let minute = Int(value / 60);
        let second = Int(value.truncatingRemainder(dividingBy: 60));
        let msecond = Int((value - floor(value)) * 100);
        return String(
            format:"%02d:%02d:%02d",
            arguments:[minute, second, msecond])
    }
    init(){
        durationStr = MainView.descriptTimeInterval(player.duration)
    }
    @State var slideValue:Double = 1.0;
    @State var volume: Float = 1.0;
    let durationStr:String
    var body: some View {
        VStack(alignment:.leading){
            VStack(alignment:.leading){
                ForEach(ainfos, id: \.key){ info in
                    HStack(alignment: .top){
                        Text("\(info.key)：")
                        Text(info.value)
                    }
                }
                HStack(alignment: .top){
                    Text("時：")
                    Text("\(durationStr) / \(MainView.descriptTimeInterval(player.currentTime))")
                }
            }.padding(EdgeInsets(top: 0, leading: 5, bottom: 5, trailing: 0))
            HStack{
                Button((player.isPlaying ? "暫" : "播"), action:{
                    if player.isPlaying {
                        player.pause();
                    }
                    else{
                        player.play();
                    }
                })
                Button("停", action:{
                    player.stop();
                    player.currentTime = 0;
                })
                Slider(
                    value: $volume ,in: 0.0 ... 1.0,
                    onEditingChanged:{ _ in
                        player.setVolume(self.volume, fadeDuration: 0);
                    },
                    label: { Text("音：") }
                ).frame(maxWidth: 100)
            }.padding(EdgeInsets(top: 0, leading: 5, bottom: 5, trailing: 0))
            MySlider(value:$slideValue, rangeIn:0.0...player.duration,
                onEditChanged:{ val in
                    player.currentTime = val
                }).padding(EdgeInsets(top: 0, leading: 5, bottom: 5, trailing: 5))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear{
            queue.async{
                while(player != nil){
                    usleep(10000);
                    self.slideValue = player.currentTime
                }
            }
        }
    }
}

struct MySlider: View{
    init(value:Binding<Double>, rangeIn:ClosedRange<Double>, onEditChanged:((Double)->())? = nil){
        self._bindingVal = value;
        self._rangeIn = State(initialValue: rangeIn)
        self._inProportion = 
            State(
                initialValue: MySlider.computeValWidPrpportion(value: value.wrappedValue, range: rangeIn)
                )
        self.outProportion = MySlider.computeValWidPrpportion(value: value.wrappedValue, range: rangeIn)
        self.onEditChanged = onEditChanged
    }
    @Binding var bindingVal: Double
    @State var rangeIn: ClosedRange<Double>;
    var outProportion:CGFloat;
    @State var fromIn:Bool = false;
    @State var inProportion:CGFloat;
    var onEditChanged: ((Double)->())?;
    static func computeValWidPrpportion(value:Double, range: ClosedRange<Double>)->CGFloat{
        var temp = value / Double(range.upperBound - range.lowerBound);
        if temp>=1 {temp = 1;}
        if temp<=0 {temp = 0;}
        return CGFloat(temp);
    }
    static func computeValWidPrpportion(value: DragGesture.Value, geometry: GeometryProxy)->CGFloat{
        var temp = value.location.x/geometry.size.width;
        if temp>=1 {temp = 1;}
        if temp<=0 {temp = 0;}
        return CGFloat(temp);
    }
    var body: some View{
        GeometryReader { geometry in
        ZStack(alignment: .leading){
            Rectangle()
                .fill(Color.gray)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width:geometry.size.width, height:10)
                .gesture(
                    DragGesture(minimumDistance: 0)
                    .onChanged{ value in
                        self.inProportion = 
                            MySlider.computeValWidPrpportion(value: value, geometry: geometry)
                        self.fromIn = true;
                    }
                    .onEnded{ value in
                        let scale:Double = Double(self.rangeIn.upperBound - self.rangeIn.lowerBound)
                        self.bindingVal = Double(self.inProportion) * scale
                        self.fromIn = false;
                        if self.onEditChanged != nil{
                            self.onEditChanged!(self.bindingVal)
                        }
                    }
                ) 
            Rectangle()
                .fill(Color.blue)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width:geometry.size.width*(self.fromIn ? self.inProportion : self.outProportion), height:8)
                .gesture(
                    DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        self.inProportion = 
                            MySlider.computeValWidPrpportion(value: value, geometry: geometry)
                        self.fromIn = true;
                    }
                    .onEnded{ value in
                        let scale:Double = Double(self.rangeIn.upperBound - self.rangeIn.lowerBound)
                        self.bindingVal = Double(self.inProportion) * scale
                        self.fromIn = false;
                        if self.onEditChanged != nil{
                            self.onEditChanged!(self.bindingVal)
                        }
                    }
                )
            
        }}.frame(minHeight:15)
    }
}

extension NSApplication {
    public func run<V: View>(@ViewBuilder view: () -> V) {
        let appDelegate = AppDelegate(view())
        NSApp.setActivationPolicy(.regular)
        mainMenu = customMenu
        delegate = appDelegate
        run()
    }
}

// Inspired by https://www.cocoawithlove.com/2010/09/minimalist-cocoa-programming.html

extension NSApplication {
    var customMenu: NSMenu {
        let appMenu = NSMenuItem()
        appMenu.submenu = NSMenu()
        let appName = ProcessInfo.processInfo.processName
        appMenu.submenu?.addItem(NSMenuItem(title: "About \(appName)", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: ""))
        appMenu.submenu?.addItem(NSMenuItem.separator())
        let services = NSMenuItem(title: "Services", action: nil, keyEquivalent: "")
        self.servicesMenu = NSMenu()
        services.submenu = self.servicesMenu
        appMenu.submenu?.addItem(services)
        appMenu.submenu?.addItem(NSMenuItem.separator())
        appMenu.submenu?.addItem(NSMenuItem(title: "Hide \(appName)", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h"))
        let hideOthers = NSMenuItem(title: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.submenu?.addItem(hideOthers)
        appMenu.submenu?.addItem(NSMenuItem(title: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: ""))
        appMenu.submenu?.addItem(NSMenuItem.separator())
        appMenu.submenu?.addItem(NSMenuItem(title: "Quit \(appName)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        
        let windowMenu = NSMenuItem()
        windowMenu.submenu = NSMenu(title: "Window")
        windowMenu.submenu?.addItem(NSMenuItem(title: "Minmize", action: #selector(NSWindow.miniaturize(_:)), keyEquivalent: "m"))
        windowMenu.submenu?.addItem(NSMenuItem(title: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: ""))
        windowMenu.submenu?.addItem(NSMenuItem.separator())
        windowMenu.submenu?.addItem(NSMenuItem(title: "Show All", action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: "m"))
        let mainMenu = NSMenu(title: "Main Menu")
        mainMenu.addItem(appMenu)
        mainMenu.addItem(windowMenu)
        return mainMenu
        
    }
}

class AppDelegate<V: View>: NSObject, NSApplicationDelegate, NSWindowDelegate {
    init(_ contentView: V) {
        self.contentView = contentView
        
    }
    var window: NSWindow!
    var hostingView: NSView?
    var contentView: V
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        player.stop()
        player = nil;
        NSApplication.shared.terminate(self)
        return true
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 300),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        window.center()
        window.setFrameAutosaveName("Main Window")
        hostingView = NSHostingView(rootView: contentView)
        window.contentView = hostingView
        window.makeKeyAndOrderFront(nil)
        window.delegate = self
        window.title = "afplay-gui (徑：\(CommandLine.arguments[1]))"
        NSApp.activate(ignoringOtherApps: true)
    }
}