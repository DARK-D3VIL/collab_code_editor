// app/assets/javascripts/conflict_notification_manager.js
class ConflictNotificationManager {
  constructor() {
    this.activeConflicts = new Map();
    this.notificationContainer = null;
    this.init();
  }

  init() {
    // Create notification container if it doesn't exist
    this.ensureNotificationContainer();
    
    // Listen for conflict-related ActionCable messages
    this.setupActionCableListeners();
  }

  ensureNotificationContainer() {
    this.notificationContainer = document.getElementById('conflict-notifications');
    
    if (!this.notificationContainer) {
      this.notificationContainer = document.createElement('div');
      this.notificationContainer.id = 'conflict-notifications';
      this.notificationContainer.className = 'conflict-notifications-container';
      document.body.appendChild(this.notificationContainer);
    }
  }

  setupActionCableListeners() {
    // This will be called when ActionCable receives conflict messages
    // Integration with the main editor's ActionCable connection
    if (window.collaborativeEditor) {
      window.collaborativeEditor.conflictManager = this;
    }
  }

  showConflictNotification(conflictData) {
    const { conflict_id, conflicting_user_id, lines, message, file_path } = conflictData;
    
    // Don't show duplicate notifications
    if (this.activeConflicts.has(conflict_id)) {
      return;
    }

    const notification = this.createConflictNotification(conflictData);
    this.notificationContainer.appendChild(notification);
    this.activeConflicts.set(conflict_id, notification);

    // Auto-remove after 30 seconds if not acted upon
    setTimeout(() => {
      this.removeConflictNotification(conflict_id);
    }, 30000);
  }

  createConflictNotification(conflictData) {
    const { conflict_id, conflicting_user_id, lines, message, file_path } = conflictData;
    
    const notification = document.createElement('div');
    notification.className = 'conflict-notification alert alert-warning alert-dismissible fade show';
    notification.setAttribute('data-conflict-id', conflict_id);
    
    const userName = this.getUserName(conflicting_user_id);
    
    notification.innerHTML = `
      <div class="d-flex align-items-start">
        <div class="flex-grow-1">
          <h6 class="alert-heading mb-1">
            <i class="fas fa-exclamation-triangle me-2"></i>
            Edit Conflict
          </h6>
          <p class="mb-2">
            <strong>${userName}</strong> edited lines <strong>${lines.join(', ')}</strong> 
            in <code>${file_path}</code>
          </p>
          <div class="btn-group btn-group-sm" role="group">
            <button type="button" class="btn btn-outline-primary" 
                    onclick="conflictManager.acceptChanges('${conflict_id}')">
              <i class="fas fa-check me-1"></i>
              Accept
            </button>
            <button type="button" class="btn btn-outline-secondary" 
                    onclick="conflictManager.ignoreConflict('${conflict_id}')">
              <i class="fas fa-times me-1"></i>
              Ignore
            </button>
            <button type="button" class="btn btn-outline-info" 
                    onclick="conflictManager.viewDetails('${conflict_id}')">
              <i class="fas fa-info-circle me-1"></i>
              Details
            </button>
          </div>
        </div>
        <button type="button" class="btn-close" 
                onclick="conflictManager.dismissNotification('${conflict_id}')"
                aria-label="Close"></button>
      </div>
    `;
    
    return notification;
  }

  acceptChanges(conflictId) {
    // Send resolution request to server
    fetch(`/conflicts/${conflictId}/resolve`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content
      }
    }).then(response => {
      if (response.ok) {
        this.removeConflictNotification(conflictId);
        this.showSuccessMessage('Conflict resolved - refreshing content');
        
        // Refresh editor content if available
        if (window.collaborativeEditor) {
          window.collaborativeEditor.refreshEditor();
        }
      } else {
        this.showErrorMessage('Failed to resolve conflict');
      }
    }).catch(error => {
      console.error('Error resolving conflict:', error);
      this.showErrorMessage('Network error resolving conflict');
    });
  }

  ignoreConflict(conflictId) {
    // Send ignore request to server
    fetch(`/conflicts/${conflictId}/ignore`, {
      method: 'DELETE',
      headers: {
        'Content-Type': 'application/json',
        'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content
      }
    }).then(response => {
      if (response.ok) {
        this.removeConflictNotification(conflictId);
        this.showInfoMessage('Conflict ignored');
      } else {
        this.showErrorMessage('Failed to ignore conflict');
      }
    }).catch(error => {
      console.error('Error ignoring conflict:', error);
      this.showErrorMessage('Network error ignoring conflict');
    });
  }

  viewDetails(conflictId) {
    // Fetch conflict details and show in modal
    fetch(`/conflicts/${conflictId}`, {
      method: 'GET',
      headers: {
        'Accept': 'application/json',
        'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content
      }
    }).then(response => response.json())
      .then(data => {
        this.showConflictDetailsModal(data);
      })
      .catch(error => {
        console.error('Error fetching conflict details:', error);
        this.showErrorMessage('Failed to load conflict details');
      });
  }

  showConflictDetailsModal(conflictData) {
    // Create and show detailed conflict modal
    const modal = this.createConflictDetailsModal(conflictData);
    document.body.appendChild(modal);
    
    if (typeof bootstrap !== 'undefined' && bootstrap.Modal) {
      const bsModal = new bootstrap.Modal(modal);
      bsModal.show();
      
      // Clean up modal when hidden
      modal.addEventListener('hidden.bs.modal', () => {
        modal.remove();
      });
    }
  }

  createConflictDetailsModal(conflictData) {
    const modal = document.createElement('div');
    modal.className = 'modal fade';
    modal.setAttribute('tabindex', '-1');
    
    modal.innerHTML = `
      <div class="modal-dialog modal-lg">
        <div class="modal-content">
          <div class="modal-header">
            <h5 class="modal-title">
              <i class="fas fa-exclamation-triangle text-warning me-2"></i>
              Conflict Details
            </h5>
            <button type="button" class="btn-close" data-bs-dismiss="modal"></button>
          </div>
          <div class="modal-body">
            <div class="mb-3">
              <h6>Conflict Information</h6>
              <p><strong>Age:</strong> ${this.formatAge(conflictData.age)}</p>
              <p><strong>Lines:</strong> ${conflictData.conflict.conflicting_lines}</p>
            </div>
            <div class="mb-3">
              <h6>Current Content</h6>
              <div class="bg-light p-3 rounded">
                <code><pre>${conflictData.content.join('\n')}</pre></code>
              </div>
            </div>
          </div>
          <div class="modal-footer">
            <button type="button" class="btn btn-secondary" data-bs-dismiss="modal">Close</button>
            <button type="button" class="btn btn-primary" 
                    onclick="conflictManager.acceptChanges('${conflictData.conflict.id}'); bootstrap.Modal.getInstance(this.closest('.modal')).hide();">
              Accept Changes
            </button>
          </div>
        </div>
      </div>
    `;
    
    return modal;
  }

  dismissNotification(conflictId) {
    this.removeConflictNotification(conflictId);
  }

  removeConflictNotification(conflictId) {
    const notification = this.activeConflicts.get(conflictId);
    if (notification && notification.parentNode) {
      notification.remove();
      this.activeConflicts.delete(conflictId);
    }
  }

  getUserName(userId) {
    // Try to get user name from collaborative editor
    if (window.collaborativeEditor && window.collaborativeEditor.users.has(userId)) {
      return window.collaborativeEditor.users.get(userId).name;
    }
    return 'Another user';
  }

  formatAge(seconds) {
    if (seconds < 60) return `${Math.floor(seconds)} seconds ago`;
    if (seconds < 3600) return `${Math.floor(seconds / 60)} minutes ago`;
    return `${Math.floor(seconds / 3600)} hours ago`;
  }

  showSuccessMessage(message) {
    this.showTemporaryMessage(message, 'success');
  }

  showErrorMessage(message) {
    this.showTemporaryMessage(message, 'danger');
  }

  showInfoMessage(message) {
    this.showTemporaryMessage(message, 'info');
  }

  showTemporaryMessage(message, type) {
    const alert = document.createElement('div');
    alert.className = `alert alert-${type} alert-dismissible fade show`;
    alert.innerHTML = `
      ${message}
      <button type="button" class="btn-close" data-bs-dismiss="alert"></button>
    `;
    
    this.notificationContainer.appendChild(alert);
    
    setTimeout(() => {
      if (alert.parentNode) {
        alert.remove();
      }
    }, 3000);
  }

  // Clean up expired conflicts
  cleanup() {
    this.activeConflicts.forEach((notification, conflictId) => {
      const age = notification.getAttribute('data-age');
      if (age && Date.now() - parseInt(age) > 300000) { // 5 minutes
        this.removeConflictNotification(conflictId);
      }
    });
  }
}

// Initialize conflict manager when DOM is ready
document.addEventListener('DOMContentLoaded', function() {
  window.conflictManager = new ConflictManager();
  
  // Clean up expired conflicts every minute
  setInterval(() => {
    window.conflictManager.cleanup();
  }, 60000);
});

// CSS for conflict notifications
const style = document.createElement('style');
style.textContent = `
  .conflict-notifications-container {
    position: fixed;
    top: 80px;
    right: 20px;
    z-index: 1070;
    max-width: 400px;
    max-height: 60vh;
    overflow-y: auto;
  }
  
  .conflict-notification {
    margin-bottom: 10px;
    box-shadow: 0 4px 6px rgba(0,0,0,0.1);
    border: none;
    border-radius: 8px;
    border-left: 4px solid #ffc107;
  }
  
  .conflict-notification .btn-group {
    margin-top: 8px;
  }
  
  .conflict-notification .btn {
    font-size: 0.875rem;
    padding: 0.375rem 0.75rem;
  }
  
  .conflict-notification code {
    background-color: rgba(0,0,0,0.1);
    padding: 0.125rem 0.25rem;
    border-radius: 0.25rem;
  }
`;
document.head.appendChild(style);