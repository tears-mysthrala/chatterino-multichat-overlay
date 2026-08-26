package overlay

import "sync"

type Hub struct {
	mu           sync.RWMutex
	historyLimit int
	history      map[string][]Message
	subscribers  map[string]map[chan Message]struct{}
}

func NewHub(historyLimit int) *Hub {
	return &Hub{historyLimit: historyLimit, history: map[string][]Message{}, subscribers: map[string]map[chan Message]struct{}{}}
}

func (h *Hub) Publish(message Message) {
	h.mu.Lock()
	if message.ID != "" {
		for _, existing := range h.history[message.Panel] {
			if existing.Platform == message.Platform && existing.ID == message.ID {
				h.mu.Unlock()
				return
			}
		}
	}
	history := append(h.history[message.Panel], message)
	if len(history) > h.historyLimit {
		history = history[len(history)-h.historyLimit:]
	}
	h.history[message.Panel] = history
	for subscriber := range h.subscribers[message.Panel] {
		select {
		case subscriber <- message:
		default:
		}
	}
	h.mu.Unlock()
}

func (h *Hub) Subscribe(panel string) (<-chan Message, []Message, func()) {
	channel := make(chan Message, 32)
	h.mu.Lock()
	if h.subscribers[panel] == nil {
		h.subscribers[panel] = map[chan Message]struct{}{}
	}
	h.subscribers[panel][channel] = struct{}{}
	history := append([]Message(nil), h.history[panel]...)
	h.mu.Unlock()
	return channel, history, func() {
		h.mu.Lock()
		delete(h.subscribers[panel], channel)
		close(channel)
		h.mu.Unlock()
	}
}

func (h *Hub) Stats() (panels, subscribers, messages int) {
	h.mu.RLock()
	defer h.mu.RUnlock()
	panels = len(h.history)
	for _, history := range h.history {
		messages += len(history)
	}
	for _, panelSubscribers := range h.subscribers {
		subscribers += len(panelSubscribers)
	}
	return
}
