defmodule ExUnitOpenAPI.SchemaNamerTest do
  use ExUnit.Case, async: true

  alias ExUnitOpenAPI.SchemaNamer

  defmodule TestApp.UserController do
    # Dummy module for testing
  end

  defmodule TestApp.PostController do
    # Dummy module for testing
  end

  describe "generate/3 - inferred names" do
    test "generates name from controller and action for response" do
      context = %{
        controller: TestApp.UserController,
        action: :show,
        type: :response,
        status: 200
      }

      {name, _state} = SchemaNamer.generate(context, %{}, SchemaNamer.new_state())
      assert name == "UserResponse"
    end

    test "generates Create prefix for create action request" do
      context = %{
        controller: TestApp.UserController,
        action: :create,
        type: :request
      }

      {name, _state} = SchemaNamer.generate(context, %{}, SchemaNamer.new_state())
      assert name == "CreateUserRequest"
    end

    test "generates Update prefix for update action request" do
      context = %{
        controller: TestApp.UserController,
        action: :update,
        type: :request
      }

      {name, _state} = SchemaNamer.generate(context, %{}, SchemaNamer.new_state())
      assert name == "UpdateUserRequest"
    end

    test "generates error suffix for 404 status" do
      context = %{
        controller: TestApp.UserController,
        action: :show,
        type: :response,
        status: 404
      }

      {name, _state} = SchemaNamer.generate(context, %{}, SchemaNamer.new_state())
      assert name == "UserNotFoundError"
    end

    test "generates error suffix for 400 status" do
      context = %{
        controller: TestApp.UserController,
        action: :create,
        type: :response,
        status: 400
      }

      {name, _state} = SchemaNamer.generate(context, %{}, SchemaNamer.new_state())
      assert name == "CreateUserBadRequestError"
    end

    test "generates error suffix for 422 status" do
      context = %{
        controller: TestApp.UserController,
        action: :create,
        type: :response,
        status: 422
      }

      {name, _state} = SchemaNamer.generate(context, %{}, SchemaNamer.new_state())
      assert name == "CreateUserValidationError"
    end

    test "generates name from path when no controller" do
      context = %{
        method: "GET",
        path: "/users/:id",
        type: :response,
        status: 200
      }

      {name, _state} = SchemaNamer.generate(context, %{}, SchemaNamer.new_state())
      assert name == "UserResponse"
    end

    test "generates name from POST method" do
      context = %{
        method: "POST",
        path: "/users",
        type: :request
      }

      {name, _state} = SchemaNamer.generate(context, %{}, SchemaNamer.new_state())
      assert name == "CreateUserRequest"
    end
  end

  describe "generate/3 - test tag overrides" do
    test "uses response_schema tag when present" do
      context = %{
        controller: TestApp.UserController,
        action: :show,
        type: :response,
        status: 200,
        openapi_tags: %{response_schema: "CustomUserDetails"}
      }

      {name, _state} = SchemaNamer.generate(context, %{}, SchemaNamer.new_state())
      assert name == "CustomUserDetails"
    end

    test "uses request_schema tag when present" do
      context = %{
        controller: TestApp.UserController,
        action: :create,
        type: :request,
        openapi_tags: %{request_schema: "NewUserPayload"}
      }

      {name, _state} = SchemaNamer.generate(context, %{}, SchemaNamer.new_state())
      assert name == "NewUserPayload"
    end
  end

  describe "generate/3 - config overrides" do
    test "uses config override by controller/action/type" do
      context = %{
        controller: TestApp.UserController,
        action: :show,
        type: :response,
        status: 200
      }

      config = %{
        schema_names: %{
          {TestApp.UserController, :show, :response, 200} => "UserProfile"
        }
      }

      {name, _state} = SchemaNamer.generate(context, config, SchemaNamer.new_state())
      assert name == "UserProfile"
    end

    test "uses config override for request by controller/action" do
      context = %{
        controller: TestApp.UserController,
        action: :create,
        type: :request
      }

      config = %{
        schema_names: %{
          {TestApp.UserController, :create, :request} => "UserInput"
        }
      }

      {name, _state} = SchemaNamer.generate(context, config, SchemaNamer.new_state())
      assert name == "UserInput"
    end

    test "test tag takes precedence over config" do
      context = %{
        controller: TestApp.UserController,
        action: :show,
        type: :response,
        status: 200,
        openapi_tags: %{response_schema: "TagOverride"}
      }

      config = %{
        schema_names: %{
          {TestApp.UserController, :show, :response, 200} => "ConfigOverride"
        }
      }

      {name, _state} = SchemaNamer.generate(context, config, SchemaNamer.new_state())
      assert name == "TagOverride"
    end
  end

  describe "generate/3 - collision resolution" do
    test "appends number on collision" do
      context = %{
        controller: TestApp.UserController,
        action: :show,
        type: :response,
        status: 200
      }

      state = SchemaNamer.new_state()

      {name1, state} = SchemaNamer.generate(context, %{}, state)
      assert name1 == "UserResponse"

      {name2, state} = SchemaNamer.generate(context, %{}, state)
      assert name2 == "UserResponse2"

      {name3, _state} = SchemaNamer.generate(context, %{}, state)
      assert name3 == "UserResponse3"
    end
  end

  describe "new_state/0" do
    test "returns initial state" do
      state = SchemaNamer.new_state()
      assert state.used_names == MapSet.new()
      assert state.name_counts == %{}
    end
  end

  describe "config_key/4" do
    test "builds request key" do
      key = SchemaNamer.config_key(:request, TestApp.UserController, :create)
      assert key == {TestApp.UserController, :create, :request}
    end

    test "builds response key with status" do
      key = SchemaNamer.config_key(:response, TestApp.UserController, :show, 200)
      assert key == {TestApp.UserController, :show, :response, 200}
    end
  end
end
