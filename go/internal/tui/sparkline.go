// SPDX-License-Identifier: MIT

package tui

import (
	"fmt"
	"strings"

	"github.com/charmbracelet/lipgloss"
)

var sparkChars = []rune{'▁', '▂', '▃', '▄', '▅', '▆', '▇', '█'}

type SparklineModel struct {
	Data   []float64
	Label  string
	Max    float64
	Color  lipgloss.Color
	width  int
	last   float64
	hasVal bool
}

func NewSparklineModel(label string, maxDataPoints int, color lipgloss.Color) *SparklineModel {
	if maxDataPoints <= 0 {
		maxDataPoints = 30
	}

	data := generateSampleData(maxDataPoints)

	return &SparklineModel{
		Data:  data,
		Label: label,
		Max:   100.0,
		Color: color,
		width: 30,
	}
}

func NewSparklineWithData(label string, data []float64, max float64, color lipgloss.Color) *SparklineModel {
	return &SparklineModel{
		Data:  data,
		Label: label,
		Max:   max,
		Color: color,
		width: 30,
	}
}

func (s *SparklineModel) AddDataPoint(value float64) {
	s.Data = append(s.Data, value)
	if len(s.Data) > s.width {
		s.Data = s.Data[len(s.Data)-s.width:]
	}
	s.last = value
	s.hasVal = true
}

func (s *SparklineModel) SetMax(max float64) {
	s.Max = max
}

func (s *SparklineModel) Render() string {
	if len(s.Data) == 0 {
		return s.renderEmpty()
	}

	maxVal := s.Max
	if maxVal == 0 {
		maxVal = 1
	}

	for _, v := range s.Data {
		if v > maxVal {
			maxVal = v
		}
	}

	sparkline := ""
	for _, v := range s.Data {
		normalized := v / maxVal
		if normalized < 0 {
			normalized = 0
		}
		if normalized > 1 {
			normalized = 1
		}

		idx := int(normalized * float64(len(sparkChars)-1))
		if idx >= len(sparkChars) {
			idx = len(sparkChars) - 1
		}
		if idx < 0 {
			idx = 0
		}

		ch := sparkChars[idx]
		style := lipgloss.NewStyle().Foreground(s.Color)
		sparkline += style.Render(string(ch))
	}

	label := sparkLabelStyle.Render(s.Label)

	currentVal := ""
	if s.hasVal {
		currentVal = sparkValueStyle.Render(fmt.Sprintf("%.1f", s.last))
	} else if len(s.Data) > 0 {
		currentVal = sparkValueStyle.Render(fmt.Sprintf("%.1f", s.Data[len(s.Data)-1]))
	}

	return fmt.Sprintf("  %s %s %s", label, sparkline, currentVal)
}

func (s *SparklineModel) renderEmpty() string {
	label := sparkLabelStyle.Render(s.Label)
	empty := sparklineStyle.Render(strings.Repeat("▁", s.width))
	value := sparkValueStyle.Render("—")
	return fmt.Sprintf("  %s %s %s", label, empty, value)
}

func generateSampleData(n int) []float64 {
	data := make([]float64, n)
	for i := 0; i < n; i++ {
		data[i] = 30.0 + float64(i%20)*2.5 + float64(i%5)*3.0
	}
	return data
}
