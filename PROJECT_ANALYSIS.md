# Smart Classroom Monitoring - Project Analysis

## Overview
This project is a sophisticated **Smart Classroom Monitoring System** that integrates **Flutter**, **Firebase**, and **Machine Learning** to automate student task assignments based on behavioral data (violations).

## Core Architecture
- **Frontend**: Flutter-based mobile/web application (`lib/`).
- **Backend & Automation**: Firebase Cloud Functions (`functions/`) and Python-based ML API (`ml/`).
- **Data Layer**: Firestore for real-time state management and data storage.
- **Media Storage**: Firebase Storage (and Cloudinary integration) for task proofs.

## Key Features
1. **Real-time Violation Tracking**: Monitors student behavior (likely through a native foreground service mentioned in conversation history) and stores violations in Firestore.
2. **ML Task Automation**:
   - **Data Aggregation**: Collects violation data from the last 48 hours per student.
   - **Level Classification**: Uses a Logistic Regression model to classify students into **Easy**, **Medium**, or **Hard** levels based on violation counts.
   - **Automated Assignment**: Hourly scheduled tasks create automated assignments for students based on their predicted level.
3. **Automated Verification**: Cloud Functions automatically review submitted proofs for automated tasks, streamlining the admin's workflow.
4. **Admin Dashboard**: Comprehensive monitoring and attendance management screens.

## Technical Stack
- **Languages**: Dart (Flutter), Python (ML), JavaScript (Cloud Functions).
- **Frameworks**: Flutter, scikit-learn (ML), Flask (ML API).
- **Security**: Granular Firestore rules for role-based access (Admin/Student).

---

## 3D Model Implementation Plan
To enhance the visual representation of the classroom, we are introducing a **3D Visualizer**.

- **Folder**: `3d_visualizer/`
- **Technology**: Three.js (Web-based 3D modeling).
- **Model**: A procedural 3D classroom scene showing desks, a teacher's desk, and status-coded student nodes.
- **Interactive Elements**: Hover over students to see their violation status and predicted task level.

---
*Created by Antigravity on 2026-03-31*
