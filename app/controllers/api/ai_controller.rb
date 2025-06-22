# app/controllers/api/ai_controller.rb
class Api::AiController < ApplicationController
  # Skip CSRF for API endpoints
  skip_before_action :verify_authenticity_token
  
  # Don't require authentication for now (you can add it later)
  # before_action :authenticate_user!
  
  def completions
    Rails.logger.info "🤖 AI Completion request received"
    Rails.logger.info "   Project ID: #{params[:project_id]}"
    Rails.logger.info "   Language: #{params[:language]}"
    Rails.logger.info "   File path: #{params[:file_path]}"
    Rails.logger.info "   Cursor: Line #{params.dig(:cursor_position, :line)}, Col #{params.dig(:cursor_position, :column)}"
    Rails.logger.info "   Content length: #{params[:content]&.length || 0} chars"
    
    begin
      # Validate required parameters
      unless params[:project_id] && params[:content] && params[:cursor_position]
        return render json: {
          status: 'error',
          message: 'Missing required parameters: project_id, content, cursor_position'
        }, status: 400
      end
      
      # Find project (skip user check for now)
      project = Project.find_by(id: params[:project_id])
      unless project
        return render json: {
          status: 'error',
          message: 'Project not found'
        }, status: 404
      end
      
      Rails.logger.info "   Found project: #{project.name}"
      
      # Check if AI training is enabled for this project
      unless project.ai_training_enabled?
        return render json: {
          status: 'error',
          message: 'AI completion is not enabled for this project'
        }, status: 403
      end
      
      Rails.logger.info "   AI training enabled: #{project.ai_training_enabled?}"
      Rails.logger.info "   AI training status: #{project.ai_training_status}"
      Rails.logger.info "   AI model available: #{project.ai_model_available?}"
      
      # For development/testing, allow completions even if model isn't fully trained
      if Rails.env.production? && !project.ai_model_available?
        return render json: {
          status: 'error',
          message: 'AI model is not yet trained for this project. Please wait for training to complete.',
          suggestion: 'Try again in a few minutes or check the project training status.',
          training_status: project.ai_training_status
        }, status: 425 # Too Early
      end
      
      # Prepare cursor position
      cursor_position = {
        line: params.dig(:cursor_position, :line)&.to_i || 1,
        column: params.dig(:cursor_position, :column)&.to_i || 1
      }
      
      # Prepare options
      options = {
        max_suggestions: params[:max_suggestions]&.to_i || 5,
        language: params[:language] || 'text',
        file_path: params[:file_path] || 'unknown'
      }
      
      Rails.logger.info "   Calling AI service..."
      Rails.logger.info "   Options: #{options}"
      
      # Call AI completion service
      ai_response = AiCompletionService.generate_completions(
        params[:project_id].to_i,
        params[:content],
        cursor_position,
        options
      )
      
      Rails.logger.info "   AI service response: #{ai_response.inspect}"
      
      if ai_response && ai_response['completions']
        completions = ai_response['completions'].map do |completion|
          {
            text: completion['text'] || completion[:text] || '',
            confidence: completion['confidence'] || completion[:confidence] || 0.8,
            type: completion['type'] || completion[:type] || 'suggestion',
            description: completion['description'] || completion[:description] || 'AI suggestion'
          }
        end
        
        Rails.logger.info "✅ Generated #{completions.length} completions"
        
        render json: {
          status: 'success',
          completions: completions,
          latency_ms: ai_response['latency_ms'] || 0,
          model_used: ai_response['model_used'] || 'base',
          personalized: ai_response['personalized'] || false
        }
        
      elsif ai_response && ai_response['error']
        Rails.logger.error "❌ AI service error: #{ai_response['error']}"
        
        render json: {
          status: 'error',
          message: "AI service error: #{ai_response['error']}"
        }, status: 502
        
      else
        Rails.logger.warn "⚠️ No completions generated or empty response"
        Rails.logger.warn "   Full AI response: #{ai_response.inspect}"
        
        # Create a fallback completion for testing
        fallback_completions = [{
          text: "\n## Next Steps\n\n- Add more documentation\n- Include installation instructions",
          confidence: 0.6,
          type: "fallback",
          description: "Fallback suggestion (AI service unavailable)"
        }]
        
        render json: {
          status: 'success',
          completions: fallback_completions,
          message: 'Using fallback suggestions (AI service may be unavailable)'
        }
      end
      
    rescue => e
      Rails.logger.error "❌ AI completion controller error: #{e.message}"
      Rails.logger.error "   Backtrace: #{e.backtrace.first(5).join("\n")}"
      
      render json: {
        status: 'error',
        message: 'Internal server error while generating completions',
        details: Rails.env.development? ? e.message : nil
      }, status: 500
    end
  end
  
  private
  
  def authenticate_user!
    # Check if user is logged in via session or cookies
    if current_user.nil?
      render json: {
        status: 'error',
        message: 'Authentication required'
      }, status: 401
      return
    end
  end
end