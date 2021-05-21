//
//  ViewController.swift
//  test
//
//  Created by Justin Kwok Lam CHAN on 4/4/21.
//

import Charts
import UIKit
import CoreMotion
import simd

class ViewController: UIViewController, ChartViewDelegate {
    
    @IBOutlet weak var lineChartView: LineChartView!
    @IBOutlet weak var startButton: UIButton!
    @IBOutlet weak var stopButton: UIButton!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view.
        
        self.lineChartView.delegate = self
        
        let set_a: LineChartDataSet = LineChartDataSet(entries: [ChartDataEntry](), label: "only gyroscope")
        set_a.drawCirclesEnabled = false
        set_a.setColor(UIColor.blue)

        let set_b: LineChartDataSet = LineChartDataSet(entries: [ChartDataEntry](), label: "only accelerometer")
        set_b.drawCirclesEnabled = false
        set_b.setColor(UIColor.red)
        
        let set_c: LineChartDataSet = LineChartDataSet(entries: [ChartDataEntry](), label: "complementary filter")
        set_c.drawCirclesEnabled = false
        set_c.setColor(UIColor.green)
        self.lineChartView.data = LineChartData(dataSets: [set_a,set_b,set_c])
    }
    
    @IBAction func startSensors(_ sender: Any) {
        startAccelerometers()
        startGyros()
        startButton.isEnabled = false
        stopButton.isEnabled = true
    }
    
    @IBAction func stopSensors(_ sender: Any) {
        stopAccels()
        stopGyros()
        startButton.isEnabled = true
        stopButton.isEnabled = false
    }
    
    let motion = CMMotionManager()
    var counter:Double = 0
    
    var timer_accel:Timer?
    var accel_file_url:URL?
    var accel_fileHandle:FileHandle?
    
    var timer_gyro:Timer?
    var gyro_file_url:URL?
    var gyro_fileHandle:FileHandle?
    
    let xrange:Double = 500
    
    // identity quarternian q(0)
    var q = simd_quatd(ix: 0, iy: 0, iz: 0, r: 1)
    var q_a = simd_quatd(ix: 0, iy: 0, iz: 0, r: 1)
    // 100 Hz is the max rate
    var delta_t = (1.0 / 100.0)
    // Constant gravity field [x,y,z]
    var gravity = simd_double3(0.0, -1.0, 0.0)
    
    let group_size = 5.0
    let up_oreintaion = simd_double3(0.0, 1.0, 0.0)
    var a_group:[simd_double3]=[simd_double3(1000, 10000, 1000)]
    let alpha_male = 0.00008
    var phi3:Double?
    var deg3:Double?
    let threshHold = 10.0
    
    func startAccelerometers() {
       // Make sure the accelerometer hardware is available.
       if self.motion.isAccelerometerAvailable {
        // sampling rate can usually go up to at least 100 Hz
        // if you set it beyond hardware capabilities, phone will use max rate
        self.motion.accelerometerUpdateInterval = delta_t  // 100 Hz is the max rate
          self.motion.startAccelerometerUpdates()
        
        // create the data file we want to write to
        // initialize file with header line
        do {
            // get timestamp in epoch time
            let ts = NSDate().timeIntervalSince1970
            let file = "accel_file_\(ts).txt"
            if let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                accel_file_url = dir.appendingPathComponent(file)
            }
            
            // write first line of file
            try "ts,x,y,z\n".write(to: accel_file_url!, atomically: true, encoding: String.Encoding.utf8)

            accel_fileHandle = try FileHandle(forWritingTo: accel_file_url!)
            accel_fileHandle!.seekToEndOfFile()
        } catch {
            print("Error writing to file \(error)")
        }
        
          // Configure a timer to fetch the data.
          self.timer_accel = Timer(fire: Date(), interval: (delta_t),
                                   repeats: true, block: { [self] (timer) in
             // Get the accelerometer data.
            if a_group[0] == simd_double3(1000, 10000, 1000) {
             if let data = self.motion.accelerometerData {
                let x = data.acceleration.x
                let y = data.acceleration.y
                let z = data.acceleration.z
                var fresh_x = x + -0.005467154705172836
                var fresh_y = y + 0.00274799831945316
                var fresh_z = z + -0.010190491119318655
                
                if a_group.count == 1 {
                    a_group.append([fresh_x, fresh_y, fresh_z])
                }

                else if(a_group.count > 1){
                    if abs(x - a_group.last![0]) > threshHold || abs(y - a_group.last![1]) > threshHold || abs(z - a_group.last![2]) > threshHold {
                        print("rejected \(abs(x - a_group.last![0])) \(abs(y - a_group.last![1])) \(abs(z - a_group.last![2]))")
                    } else {
                        a_group.append([fresh_x, fresh_y, fresh_z])
                    }

                    if(a_group.count == Int(group_size) + 1) {

                        a_group.remove(at: 0)
    //                    print("Group of accel vals: \(a_group)")
                    }
                }
                let timestamp = NSDate().timeIntervalSince1970
                let text = "\(timestamp), \(x), \(y), \(z)\n"
//                print ("A: \(text)")
                
                self.accel_fileHandle!.write(text.data(using: .utf8)!)
             }
            }
          })

          // Add the timer to the current run loop.
        RunLoop.current.add(self.timer_accel!, forMode: RunLoop.Mode.default)
       }
    }
    
    func startGyros() {
       if motion.isGyroAvailable {
        self.motion.gyroUpdateInterval = (delta_t * group_size).rounded() // 100 Hz is the max rate
          self.motion.startGyroUpdates()
        
        do {
            let ts = NSDate().timeIntervalSince1970
            let file = "gyro_file_\(ts).txt"
            if let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                gyro_file_url = dir.appendingPathComponent(file)
            }
            
            try "ts,x,y,z\n".write(to: gyro_file_url!, atomically: true, encoding: String.Encoding.utf8)

            gyro_fileHandle = try FileHandle(forWritingTo: gyro_file_url!)
            gyro_fileHandle!.seekToEndOfFile()
        } catch {
            print("Error writing to file \(error)")
        }
        
          // Configure a timer to fetch the accelerometer data.
          self.timer_gyro = Timer(fire: Date(), interval: ((delta_t * group_size ).rounded()),
                                  repeats: true, block: { [self] (timer) in
                                    
        if a_group[0] != simd_double3(1000, 10000, 1000) {
//              Get the gyro data.
             if let data = self.motion.gyroData {
                let x = data.rotationRate.x
                let y = data.rotationRate.y
                let z = data.rotationRate.z
          
                var w_x = x + -0.005307499035239443
                var w_y = y + 0.0076071045342757816
                var w_z = z + -0.008861463428024074
                
                let l = length(simd_double3(w_x, w_y, w_z))
                let v = simd_double3((1.0 / l) * w_x, ( 1.0 / l) * w_y, (1.0 / l) * w_z)
                // theta = l * delta_t
                var theta = l * self.delta_t * group_size
//                if (abs(theta) < still_thresh) {
//                    theta = 0.0
//                }
                // delta_t = 1/100 hz
                // set quarternian q(v,theta)
                let q_v = simd_quatd(angle: theta, axis: v)
                let new_q_Os = self.q * q_v
//                next_pos = new_q_Os.act(next_pos)
//                let phi = acos(dot(next_pos,up_oreintaion) / (length(next_pos) * length(up_oreintaion)))//tilt error just gyro
                let rotatedVector = new_q_Os.act(up_oreintaion)
                let phi = acos(dot(rotatedVector,up_oreintaion) / (length(rotatedVector) * length(up_oreintaion)))//tilt error just gyro
                var deg = (phi/Double.pi) * 180
//                print(deg)

//MARK: Acceleration
                var G_A_group:simd_double3?
                var G_A:SIMD3<Double>?
                var q_l_a:simd_quatd?
                var q_G_A:simd_quatd?
                var avg_x:simd_double1 = 0
                var avg_y:simd_double1 = 0
                var avg_z:simd_double1 = 0
                var tilt:simd_double3?
                for i in 0..<a_group.count {
                    q_l_a = simd_quatd(angle: Double.pi, axis: a_group[i])
                    q_G_A = q_l_a
                    if  a_group[i] != gravity {
                        q_G_A = self.q.normalized.inverse * q_l_a! * self.q.normalized
                    }

                    G_A = q_G_A!.act(up_oreintaion)
                    avg_x += (G_A![0] - gravity[0])
                    avg_y += (G_A![1] - gravity[1])
                    avg_z += (G_A![2] - gravity[2])

                }

                G_A_group = [avg_x/simd_double1(a_group.count), avg_y/simd_double1(a_group.count), avg_z/simd_double1(a_group.count)]
                tilt = simd_double3(G_A_group![2], 0, -G_A_group![0])
                let phi2 =  acos(dot(G_A_group!,up_oreintaion) / (length(G_A_group!) * 1.0))//tilt error just accel
                var deg2 = (phi2/Double.pi) * 180
//                print(deg2)


//MARK: TILT CORRECTION
                let qs = simd_quatd(angle: -alpha_male * phi2, axis: tilt!)
                self.q  = qs * new_q_Os
                let news = self.q.act(up_oreintaion)
                phi3 = acos(dot(news,up_oreintaion) / (length(news) * length(up_oreintaion)))//tilt error combo


                deg3 = (phi3!/Double.pi) * 180
//                print("Tilt error is \(deg)")

                a_group = [simd_double3(1000, 10000, 1000)]
                let timestamp = NSDate().timeIntervalSince1970
                let text = "\(timestamp), \(x), \(y), \(z)\n"
//                print ("G: \(text)")
                
                self.gyro_fileHandle!.write(text.data(using: .utf8)!)

                self.lineChartView.data?.addEntry(ChartDataEntry(x: Double(counter), y: deg), dataSetIndex: 0)
                self.lineChartView.data?.addEntry(ChartDataEntry(x: Double(counter), y: deg2), dataSetIndex: 1)
                self.lineChartView.data?.addEntry(ChartDataEntry(x: Double(counter), y: deg3!), dataSetIndex: 2)

                // refreshes the data in the graph
                self.lineChartView.notifyDataSetChanged()

                self.counter = self.counter + 1

                // needs to come up after notifyDataSetChanged()
                if counter < xrange {
                    self.lineChartView.setVisibleXRange(minXRange: 0, maxXRange: xrange)
                }
                else {
                    self.lineChartView.setVisibleXRange(minXRange: counter, maxXRange: counter+xrange)
                }
             }
        }
          })

          // Add the timer to the current run loop.
          RunLoop.current.add(self.timer_gyro!, forMode: RunLoop.Mode.default)
       }
    }
    
    func stopAccels() {
       if self.timer_accel != nil {
          self.timer_accel?.invalidate()
          self.timer_accel = nil

          self.motion.stopAccelerometerUpdates()
        
           accel_fileHandle!.closeFile()
       }
    }
    
    func stopGyros() {
       if self.timer_gyro != nil {
          self.timer_gyro?.invalidate()
          self.timer_gyro = nil

          self.motion.stopGyroUpdates()
          
           gyro_fileHandle!.closeFile()
       }
    }
}

