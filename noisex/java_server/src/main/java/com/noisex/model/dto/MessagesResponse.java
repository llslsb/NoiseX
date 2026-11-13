package com.noisex.model.dto;

import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;

@Data
@NoArgsConstructor
@AllArgsConstructor
public class MessagesResponse {
    private java.util.List<MessageResponse> messages;
    private boolean hasMore;
}
