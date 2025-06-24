# app/services/ai_completion_service.rb - Using Net::HTTP (no external dependencies)
require 'net/http'
require 'json'
require 'uri'

class AiCompletionService
  BASE_URI = 'http://localhost:8000/api/v1'
  DEFAULT_TIMEOUT = 30
  
  class << self
    def health_check
      Rails.logger.info "🏥 Checking AI service health at #{BASE_URI}/health"
      
      begin
        response = make_request('GET', '/health', nil, 10)
        
        Rails.logger.info "   Response code: #{response.code}"
        Rails.logger.info "   Response body: #{response.body}"
        
        if response.is_a?(Net::HTTPSuccess)
          data = JSON.parse(response.body)
          Rails.logger.info "   Parsed response: #{data.inspect}"
          
          if data.is_a?(Hash) && data['status']
            status = data['status']
            models_loaded = data['models_loaded'] || 0
            
            # Accept both 'healthy' and 'degraded' status for training
            # Models don't need to be pre-loaded for training to work
            # This allows training even if database/redis are not configured
            is_operational = ['healthy', 'degraded'].include?(status)
            
            Rails.logger.info "   Service status: #{status}"
            Rails.logger.info "   Models loaded: #{models_loaded}"
            Rails.logger.info "   Service operational: #{is_operational}"
            
            if data['database_status'] == 'unhealthy'
              Rails.logger.warn "   ⚠️ Database unhealthy but proceeding (not required for training)"
            end
            
            return is_operational
          else
            Rails.logger.error "   Invalid response format - no status field"
            return false
          end
        else
          Rails.logger.error "   Health check HTTP error: #{response.code}"
          return false
        end
        
      rescue Timeout::Error => e
        Rails.logger.error "   Health check timeout: #{e.message}"
        return false
      rescue Errno::ECONNREFUSED => e
        Rails.logger.error "   Connection failed: #{e.message}"
        return false
      rescue => e
        Rails.logger.error "   Unexpected error: #{e.class} - #{e.message}"
        return false
      end
    end
    
    def check_training_status(job_id)
      Rails.logger.info "🔍 Checking training status for job #{job_id}"
      
      begin
        response = make_request('GET', "/train/status/#{job_id}", nil, 15)
        
        Rails.logger.info "   Response code: #{response.code}"
        Rails.logger.info "   Response body: #{response.body}"
        
        if response.is_a?(Net::HTTPSuccess)
          data = JSON.parse(response.body)
          Rails.logger.info "   Parsed response: #{data.inspect}"
          
          if data.is_a?(Hash) && data['job_id']
            status_info = {
              'job_id' => data['job_id'],
              'status' => data['status'],
              'progress' => data['progress'] || 0,
              'message' => data['message'] || '',
              'error_message' => data['error_message'] || ''
            }
            
            Rails.logger.info "   ✅ Status: #{status_info['status']}"
            Rails.logger.info "   📊 Progress: #{status_info['progress']}%"
            Rails.logger.info "   💬 Message: #{status_info['message']}" if status_info['message'].present?
            Rails.logger.info "   ❌ Error: #{status_info['error_message']}" if status_info['error_message'].present?
            
            return status_info
          else
            Rails.logger.error "   ❌ Invalid response format - missing job_id field"
            Rails.logger.error "   📝 Response keys: #{data.keys}" if data.is_a?(Hash)
            return nil
          end
        elsif response.code == '404'
          Rails.logger.error "   🔍 Job not found in AI service (404)"
          return nil
        else
          Rails.logger.error "   ❌ Status check HTTP error: #{response.code} #{response.message}"
          Rails.logger.error "   📝 Response body: #{response.body}"
          return nil
        end
        
      rescue Timeout::Error => e
        Rails.logger.error "   ⏰ Status check timeout: #{e.message}"
        return nil
      rescue Errno::ECONNREFUSED => e
        Rails.logger.error "   🔌 Connection failed: #{e.message}"
        return nil
      rescue JSON::ParserError => e
        Rails.logger.error "   📄 JSON parse error: #{e.message}"
        Rails.logger.error "   📝 Raw response: #{response&.body}"
        return nil
      rescue => e
        Rails.logger.error "   💥 Unexpected error: #{e.class} - #{e.message}"
        Rails.logger.error "   📚 Backtrace: #{e.backtrace.first(3).join('\n   ')}"
        return nil
      end
    end
    
    # Add a manual status check method for debugging
    def debug_job_status(job_id)
      puts "🔍 Debug: Checking status for job #{job_id}"
      
      status_info = check_training_status(job_id)
      
      if status_info
        puts "✅ Job found:"
        puts "   Job ID: #{status_info['job_id']}"
        puts "   Status: #{status_info['status']}"
        puts "   Progress: #{status_info['progress']}%"
        puts "   Message: #{status_info['message']}"
        puts "   Error: #{status_info['error_message']}" if status_info['error_message'].present?
      else
        puts "❌ Job not found or error occurred"
      end
      
      status_info
    end
    
    def start_training(project_id, repository_path, force_retrain: false)
      Rails.logger.info "🚀 Starting AI training for project #{project_id}"
      
      # Convert path
      microservice_path = convert_to_microservice_path(repository_path)
      Rails.logger.info "   Microservice path: #{microservice_path}"
      
      # Check if path exists
      unless Dir.exist?(microservice_path)
        Rails.logger.error "   Repository path does not exist: #{microservice_path}"
        return nil
      end
      
      # Check for files (but proceed even if empty)
      files = Dir.glob("#{microservice_path}/**/*").select { |f| File.file?(f) }
      Rails.logger.info "   Files found: #{files.count}"
      
      if files.empty?
        Rails.logger.info "   No files found - microservice will handle empty repository"
      else
        # Show some file examples
        files.first(3).each { |f| Rails.logger.info "     - #{f}" }
      end
      
      body = {
        project_id: project_id,
        repository_path: microservice_path,
        force_retrain: force_retrain
      }
      
      begin
        response = make_request('POST', '/train/repository', body.to_json, 30)
        
        Rails.logger.info "   Training response code: #{response.code}"
        Rails.logger.info "   Training response body: #{response.body}"
        
        if response.is_a?(Net::HTTPSuccess)
          job_data = JSON.parse(response.body)
          Rails.logger.info "✅ Training started successfully!"
          Rails.logger.info "   Job ID: #{job_data['job_id']}"
          Rails.logger.info "   Status: #{job_data['status']}"
          return job_data
        else
          Rails.logger.error "❌ Training request failed: #{response.code}"
          begin
            error_data = JSON.parse(response.body)
            Rails.logger.error "   Error: #{error_data['detail']}" if error_data['detail']
          rescue
            Rails.logger.error "   Raw error: #{response.body}"
          end
          return nil
        end
        
      rescue => e
        Rails.logger.error "❌ Training request exception: #{e.message}"
        return nil
      end
    end
    
    def generate_completions(project_id, content, cursor_position, options = {})
      Rails.logger.info "💡 Generating completions for project #{project_id}"
      
      begin
        body = {
          project_id: project_id,
          content: content,
          cursor_position: cursor_position,
          max_suggestions: options[:max_suggestions] || 5,
          language: options[:language] || 'ruby'
        }
        
        response = make_request('POST', '/completions', body.to_json, 15)
        
        if response.is_a?(Net::HTTPSuccess)
          data = JSON.parse(response.body)
          Rails.logger.info "   Generated #{data['completions']&.length || 0} completions"
          return data
        else
          Rails.logger.error "   Completions request failed: #{response.code}"
          return { 'completions' => [], 'error' => 'Request failed' }
        end
        
      rescue => e
        Rails.logger.error "   Completions request exception: #{e.message}"
        return { 'completions' => [], 'error' => e.message }
      end
    end
    
    private
    
    def make_request(method, path, body = nil, timeout = DEFAULT_TIMEOUT)
      uri = URI("#{BASE_URI}#{path}")
      
      http = Net::HTTP.new(uri.host, uri.port)
      http.read_timeout = timeout
      http.open_timeout = timeout
      
      case method.upcase
      when 'GET'
        request = Net::HTTP::Get.new(uri.request_uri)
      when 'POST'
        request = Net::HTTP::Post.new(uri.request_uri)
        request.body = body if body
        request['Content-Type'] = 'application/json'
      else
        raise "Unsupported HTTP method: #{method}"
      end
      
      http.request(request)
    end
    
    def convert_to_microservice_path(rails_path)
      # Convert Rails path to microservice accessible path
      if rails_path.start_with?('/home/dark/blogvault/collab_editor/')
        rails_path
      elsif rails_path.start_with?('storage/')
        File.join('/home/dark/blogvault/collab_editor', rails_path)
      else
        File.join('/home/dark/blogvault/collab_editor', rails_path)
      end
    end
  end
end