// Date+Extensions.swift
import Foundation

extension Date {
    func isSameDay(as other: Date) -> Bool {
        Calendar.current.isDate(self, inSameDayAs: other)
    }

    func startOfDay() -> Date {
        Calendar.current.startOfDay(for: self)
    }
}
