use todori_domain::{Task, TaskStatus, Uuid};

pub fn greet(name: String) -> String {
    format!("Hello {name} from todori-core")
}

pub fn create_draft_task(title: String) -> String {
    let task = Task {
        id: Uuid::now_v7(),
        list_id: Uuid::now_v7(),
        parent_task_id: None,
        title,
        note: String::new(),
        status: TaskStatus::Todo,
        priority: 0,
        due_at: None,
        scheduled_at: None,
        estimated_minutes: None,
        sort_order: "a0".to_string(),
        completed_at: None,
        closed_reason: None,
        deleted_at: None,
        assignee: None,
        created_at: 0,
        updated_at: 0,
    };

    serde_json::to_string(&task).expect("Task is serializable")
}
