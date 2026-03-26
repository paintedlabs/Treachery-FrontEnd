package com.solomon.treachery.model

import com.google.firebase.Timestamp

enum class FriendRequestStatus(val value: String) {
    PENDING("pending"),
    ACCEPTED("accepted"),
    DECLINED("declined");

    companion object {
        fun fromValue(value: String): FriendRequestStatus? = entries.find { it.value == value }
    }
}

data class FriendRequest(
    val id: String = "",
    val fromUserId: String = "",
    val fromDisplayName: String = "",
    val toUserId: String = "",
    val status: FriendRequestStatus = FriendRequestStatus.PENDING,
    val createdAt: Timestamp = Timestamp.now()
) {
    fun toMap(): Map<String, Any?> = mapOf(
        "from_user_id" to fromUserId,
        "from_display_name" to fromDisplayName,
        "to_user_id" to toUserId,
        "status" to status.value,
        "created_at" to createdAt
    )

    companion object {
        fun fromMap(id: String, data: Map<String, Any?>): FriendRequest = FriendRequest(
            id = id,
            fromUserId = data["from_user_id"] as? String ?: "",
            fromDisplayName = data["from_display_name"] as? String ?: "",
            toUserId = data["to_user_id"] as? String ?: "",
            status = FriendRequestStatus.fromValue(data["status"] as? String ?: "") ?: FriendRequestStatus.PENDING,
            createdAt = data["created_at"] as? Timestamp ?: Timestamp.now()
        )
    }
}
