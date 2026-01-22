import SwiftUI
import UIKit

/// A UIKit-based wheel picker that doesn't have the NaN issues of SwiftUI's Picker
/// This wraps UIPickerView to provide stable rendering during view transitions
struct UIKitWheelPicker: UIViewRepresentable {
    let range: ClosedRange<Int>
    @Binding var selection: Int

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> UIPickerView {
        let picker = UIPickerView()
        picker.delegate = context.coordinator
        picker.dataSource = context.coordinator

        // Select the current value (clamped to valid range)
        let safeSelection = max(range.lowerBound, min(range.upperBound, selection))
        let index = safeSelection - range.lowerBound
        if index >= 0 && index < range.count {
            picker.selectRow(index, inComponent: 0, animated: false)
        }

        return picker
    }

    func updateUIView(_ picker: UIPickerView, context: Context) {
        let safeSelection = max(range.lowerBound, min(range.upperBound, selection))
        let index = safeSelection - range.lowerBound
        let currentRow = picker.selectedRow(inComponent: 0)

        if index >= 0 && index < range.count && currentRow != index {
            picker.selectRow(index, inComponent: 0, animated: false)
        }
    }

    class Coordinator: NSObject, UIPickerViewDelegate, UIPickerViewDataSource {
        let parent: UIKitWheelPicker

        init(_ parent: UIKitWheelPicker) {
            self.parent = parent
        }

        func numberOfComponents(in pickerView: UIPickerView) -> Int {
            1
        }

        func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int {
            parent.range.count
        }

        func pickerView(_ pickerView: UIPickerView, titleForRow row: Int, forComponent component: Int) -> String? {
            String(parent.range.lowerBound + row)
        }

        func pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
            let newValue = parent.range.lowerBound + row
            if parent.selection != newValue {
                parent.selection = newValue
            }
        }
    }
}
